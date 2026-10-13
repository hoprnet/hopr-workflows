import fs from "node:fs";
import path from "node:path";
import { Readable } from "node:stream";
import { CarWriter } from "@ipld/car";
import { MemoryBlockstore } from "blockstore-core";
import { importer } from "ipfs-unixfs-importer";

const src = process.argv[2];
const carPath = process.argv[3];

if (!src || !carPath) {
  console.error("❌ Usage: node pack-car.mjs <src_dir> <car_path>");
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

// Pack the source directory into a single-root CAR file (UnixFS, CIDv1).
// The root CID is deterministic for a given directory content, so every
// provider that imports this CAR serves the exact same CID.
async function packCar() {
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

  // Print only JSON (deploy scripts parse last line)
  console.log(
    JSON.stringify({
      root: root.toString(),
      size,
      fileCount: files.length,
    }),
  );
}

await packCar();
