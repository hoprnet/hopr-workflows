import fs from "node:fs";
import * as tus from "tus-js-client";

const PINATA_JWT = process.env.PINATA_JWT;
const UPLOAD_TIMEOUT_MS =
  Number.parseInt(process.env.UPLOAD_TIMEOUT_MS || "", 10) || 300000;
const carPath = process.argv[2];
const pinName = process.argv[3];
const expectedRoot = process.argv[4];

if (!PINATA_JWT || !carPath || !pinName || !expectedRoot) {
  console.error(
    "❌ Usage: PINATA_JWT=<token> node upload-pinata.mjs <car_path> <pin_name> <expected_root>",
  );
  process.exit(1);
}

if (!fs.existsSync(carPath) || !fs.statSync(carPath).isFile()) {
  console.error(`❌ Error: CAR file does not exist: ${carPath}`);
  process.exit(1);
}

const size = fs.statSync(carPath).size;

// Pinata rejects uploads above 25 GB (15 GB recommended).
const PINATA_MAX_BYTES = 25 * 1024 * 1024 * 1024;
if (size > PINATA_MAX_BYTES) {
  console.error(
    `❌ Error: CAR file is ${size} bytes, above Pinata's 25 GB upload cap`,
  );
  process.exit(1);
}

// The v3 upload endpoint is TUS-compatible and TUS is required above ~100 MB,
// so every upload goes through TUS: one code path for any size. The `car`
// upload-metadata key makes Pinata import the CAR instead of re-hashing it,
// and `network=public` is mandatory — the default is private, which is not
// announced to the IPFS network.
// PINATA_UPLOAD_ENDPOINT is an override for tests only.
const ENDPOINT =
  process.env.PINATA_UPLOAD_ENDPOINT || "https://uploads.pinata.cloud/v3/files";
// Chunk size shipped by Pinata's own SDK for its TUS uploads.
const CHUNK_SIZE = 52428801;

function uploadCar() {
  return new Promise((resolve, reject) => {
    let uploadCid = null;
    let stallTimer = null;
    let lastLoggedPercent = -10;

    const upload = new tus.Upload(fs.createReadStream(carPath), {
      endpoint: ENDPOINT,
      uploadSize: size,
      chunkSize: CHUNK_SIZE,
      retryDelays: [1000, 2000, 4000, 8000],
      headers: { Authorization: `Bearer ${PINATA_JWT}` },
      metadata: {
        filename: `${pinName}.car`,
        filetype: "application/vnd.ipld.car",
        network: "public",
        car: "true",
      },
      onProgress(bytesUploaded, bytesTotal) {
        armStallTimer();
        const percent = Math.floor((bytesUploaded / bytesTotal) * 100);
        if (percent >= lastLoggedPercent + 10) {
          lastLoggedPercent = percent;
          console.error(
            `📤 Uploaded ${percent}% (${bytesUploaded}/${bytesTotal} bytes)`,
          );
        }
      },
      onAfterResponse(_req, res) {
        // The final PATCH answers with the imported root CID.
        const cid = res.getHeader("upload-cid");
        if (cid) {
          uploadCid = cid;
        }
      },
      onSuccess() {
        clearTimeout(stallTimer);
        resolve(uploadCid);
      },
      onError(error) {
        clearTimeout(stallTimer);
        reject(error);
      },
    });

    const armStallTimer = () => {
      clearTimeout(stallTimer);
      stallTimer = setTimeout(() => {
        upload.abort();
        reject(new Error(`Upload made no progress for ${UPLOAD_TIMEOUT_MS}ms`));
      }, UPLOAD_TIMEOUT_MS);
    };

    console.error(
      `📤 Uploading CAR to Pinata via TUS (${size} bytes, name "${pinName}")...`,
    );
    armStallTimer();
    upload.start();
  });
}

let cid;
try {
  cid = await uploadCar();
} catch (error) {
  const status = error?.originalResponse?.getStatus?.();
  console.error(`❌ Pinata upload failed: ${error.message}`);
  if (status === 401 || status === 403) {
    console.error(
      "❌ Authentication/authorization failed - the JWT needs the org:files:write scope, and CAR uploads require a paid Pinata plan",
    );
  }
  const body = error?.originalResponse?.getBody?.();
  if (body) {
    console.error(`   Response: ${String(body).substring(0, 300)}`);
  }
  process.exit(1);
}

if (!cid) {
  console.error(
    "❌ Pinata did not return an upload-cid header — cannot confirm the imported root CID",
  );
  process.exit(1);
}

// The root must be exactly what we packed locally; a different CID would mean
// Pinata re-interpreted the CAR and the published URLs would not match it.
if (cid.toLowerCase() !== expectedRoot.toLowerCase()) {
  console.error(
    `❌ Pinata returned CID ${cid}, expected the CAR root ${expectedRoot}`,
  );
  process.exit(1);
}

console.error(`✅ Pinata imported the CAR (root ${cid})`);

// Print only JSON (deploy scripts parse last line)
console.log(JSON.stringify({ cid, size, name: pinName }));
