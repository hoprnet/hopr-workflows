import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { Readable } from "node:stream";
import { CarWriter } from "@ipld/car";
import { MemoryBlockstore } from "blockstore-core";
import { importer } from "ipfs-unixfs-importer";
import { S3Client, HeadObjectCommand } from "@aws-sdk/client-s3";
import { Upload } from "@aws-sdk/lib-storage";

const FILEBASE_ACCESS_KEY = process.env.FILEBASE_ACCESS_KEY;
const FILEBASE_SECRET_KEY = process.env.FILEBASE_SECRET_KEY;
const FILEBASE_BUCKET = process.env.FILEBASE_BUCKET;
const UPLOAD_TIMEOUT_MS =
  Number.parseInt(process.env.UPLOAD_TIMEOUT_MS || "", 10) || 300000;
const src = process.argv[2];
const objectKey = process.argv[3];

if (
  !FILEBASE_ACCESS_KEY ||
  !FILEBASE_SECRET_KEY ||
  !FILEBASE_BUCKET ||
  !src ||
  !objectKey
) {
  console.error(
    "❌ Usage: FILEBASE_ACCESS_KEY=<key> FILEBASE_SECRET_KEY=<secret> FILEBASE_BUCKET=<bucket> node upload-filebase.mjs <build_dir> <object_key>",
  );
  process.exit(1);
}

if (!fs.existsSync(src)) {
  console.error(`❌ Error: Source directory does not exist: ${src}`);
  process.exit(1);
}
if (!fs.statSync(src).isDirectory()) {
  console.error(`❌ Error: Source path is not a directory: ${src}`);
  process.exit(1);
}

function listFiles(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...listFiles(full));
    } else if (entry.isFile()) {
      out.push(full);
    }
  }
  return out;
}

// Pack the source directory into a CAR file and return its root CID.
// Filebase imports the CAR server-side and pins the root as a single
// directory CID (UnixFS, CIDv1).
async function packCar(carPath) {
  const files = listFiles(src);
  if (files.length === 0) {
    console.error(`❌ Error: No files found in source directory: ${src}`);
    process.exit(1);
  }
  console.error(`📦 Packing ${files.length} files into a CAR file...`);

  const blockstore = new MemoryBlockstore();
  const entries = files.map((file) => ({
    path: path.relative(src, file),
    content: fs.createReadStream(file),
  }));

  let root = null;
  for await (const result of importer(entries, blockstore, {
    cidVersion: 1,
    rawLeaves: true,
    wrapWithDirectory: true,
  })) {
    root = result.cid;
  }
  if (!root) {
    throw new Error("CAR packing produced no root CID");
  }

  const { writer, out } = CarWriter.create([root]);
  const outFile = fs.createWriteStream(carPath);
  const done = new Promise((resolve, reject) => {
    outFile.on("finish", resolve);
    outFile.on("error", reject);
  });
  Readable.from(out).pipe(outFile);
  for await (const block of blockstore.getAll()) {
    await writer.put({ cid: block.cid, bytes: block.block });
  }
  await writer.close();
  await done;

  const size = fs.statSync(carPath).size;
  console.error(`✅ CAR file ready (${size} bytes, root ${root.toString()})`);
  return { root: root.toString(), size };
}

function isRetryable(error) {
  const status = error?.$metadata?.httpStatusCode;
  if (status === 429 || (status >= 500 && status < 600)) return true;
  if (status >= 400 && status < 500) return false;
  // No HTTP status: network-level error (timeout, reset, DNS) — retry.
  return true;
}

async function uploadToFilebase(retries = 3) {
  const carPath = path.join(
    process.env.TMPDIR || os.tmpdir(),
    `filebase-upload-${process.pid}.car`,
  );

  try {
    const { size } = await packCar(carPath);

    const client = new S3Client({
      endpoint: "https://s3.filebase.com",
      region: "us-east-1",
      forcePathStyle: true,
      credentials: {
        accessKeyId: FILEBASE_ACCESS_KEY,
        secretAccessKey: FILEBASE_SECRET_KEY,
      },
      requestHandler: { requestTimeout: UPLOAD_TIMEOUT_MS },
    });

    for (let attempt = 1; attempt <= retries; attempt++) {
      try {
        console.error(
          `📤 Uploading CAR to Filebase bucket "${FILEBASE_BUCKET}" (attempt ${attempt}/${retries})...`,
        );

        const upload = new Upload({
          client,
          params: {
            Bucket: FILEBASE_BUCKET,
            Key: objectKey,
            Body: fs.createReadStream(carPath),
            ContentLength: size,
            Metadata: { import: "car" },
          },
        });
        await upload.done();

        // The root CID is exposed as x-amz-meta-cid on the stored object.
        // The import can lag a moment behind the upload, so retry the read.
        let cid = null;
        for (let headAttempt = 1; headAttempt <= 5; headAttempt++) {
          const head = await client.send(
            new HeadObjectCommand({
              Bucket: FILEBASE_BUCKET,
              Key: objectKey,
            }),
          );
          cid = head.Metadata?.cid || null;
          if (cid) break;
          console.error(
            `⏳ CID not yet available (attempt ${headAttempt}/5), waiting...`,
          );
          await new Promise((resolve) => setTimeout(resolve, 3000));
        }
        if (!cid) {
          console.error(
            "❌ Uploaded object has no 'cid' metadata — is the bucket on Filebase's IPFS storage network?",
          );
          process.exit(1);
        }

        // Print only JSON (deploy scripts parse last line)
        console.log(
          JSON.stringify({
            cid,
            bucket: FILEBASE_BUCKET,
            key: objectKey,
            size,
          }),
        );
        return cid;
      } catch (error) {
        const isLastAttempt = attempt === retries;
        const status = error?.$metadata?.httpStatusCode;

        console.error(
          `❌ Filebase upload error (attempt ${attempt}/${retries}): ${error.name || "Error"}: ${error.message}`,
        );

        if (
          error.name === "InvalidAccessKeyId" ||
          error.name === "SignatureDoesNotMatch" ||
          status === 401 ||
          status === 403
        ) {
          console.error(
            "❌ Authentication failed - check FILEBASE_ACCESS_KEY and FILEBASE_SECRET_KEY",
          );
          process.exit(1);
        }
        if (error.name === "NoSuchBucket" || status === 404) {
          console.error(
            `❌ Bucket "${FILEBASE_BUCKET}" not found - check FILEBASE_BUCKET`,
          );
          process.exit(1);
        }
        if (!isRetryable(error)) {
          console.error("❌ Client error - not retrying");
          process.exit(1);
        }
        if (isLastAttempt) {
          console.error(
            "❌ Failed to upload to Filebase after all retry attempts",
          );
          process.exit(1);
        }

        const waitTime = Math.min(1000 * Math.pow(2, attempt - 1), 10000);
        console.error(`⏳ Waiting ${waitTime}ms before retry...`);
        await new Promise((resolve) => setTimeout(resolve, waitTime));
      }
    }
  } finally {
    fs.rmSync(carPath, { force: true });
  }
}

uploadToFilebase();
