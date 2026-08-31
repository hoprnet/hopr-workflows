import got from "got";

const FILEBASE_ACCESS_KEY = process.env.FILEBASE_ACCESS_KEY;
const FILEBASE_SECRET_KEY = process.env.FILEBASE_SECRET_KEY;
const FILEBASE_BUCKET = process.env.FILEBASE_BUCKET;
const PIN_TIMEOUT_MS =
  Number.parseInt(process.env.FILEBASE_PIN_TIMEOUT_MS || "", 10) || 180000;
const POLL_INTERVAL_MS =
  Number.parseInt(process.env.FILEBASE_PIN_POLL_INTERVAL_MS || "", 10) || 10000;
const cid = process.argv[2];
const pinName = process.argv[3];

if (
  !FILEBASE_ACCESS_KEY ||
  !FILEBASE_SECRET_KEY ||
  !FILEBASE_BUCKET ||
  !cid ||
  !pinName
) {
  console.error(
    "❌ Usage: FILEBASE_ACCESS_KEY=<key> FILEBASE_SECRET_KEY=<secret> FILEBASE_BUCKET=<bucket> node pin-filebase.mjs <cid> <pin_name>",
  );
  process.exit(1);
}

const API_BASE = "https://api.filebase.io/v1/ipfs";
// Filebase's per-bucket pinning token is the base64 of key:secret:bucket.
const TOKEN = Buffer.from(
  `${FILEBASE_ACCESS_KEY}:${FILEBASE_SECRET_KEY}:${FILEBASE_BUCKET}`,
).toString("base64");

const client = got.extend({
  headers: { Authorization: `Bearer ${TOKEN}` },
  timeout: { request: 30000 },
});

function done(requestid, status) {
  // Print only JSON (deploy scripts parse last line)
  console.log(JSON.stringify({ requestid, cid, status }));
}

async function createPin(retries = 3) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      console.error(
        `📌 Requesting Filebase pin for ${cid} (attempt ${attempt}/${retries})...`,
      );
      const response = await client
        .post(`${API_BASE}/pins`, {
          json: { cid, name: pinName },
        })
        .json();
      if (!response || !response.requestid) {
        throw new Error(
          `Invalid response from Filebase: ${JSON.stringify(response)}`,
        );
      }
      return response;
    } catch (error) {
      const isLastAttempt = attempt === retries;

      if (error.response) {
        const statusCode = error.response.statusCode;
        const body = error.response.body || "";

        // The pinning API rejects duplicates; an existing pin for this CID
        // is success for our purposes — look it up and reuse it.
        if (statusCode === 400 && /already pinned|duplicate/i.test(body)) {
          console.error("ℹ️  CID is already pinned on Filebase");
          const existing = await findExistingPin();
          if (existing) return existing;
          return { requestid: "already-pinned", status: "pinned" };
        }

        console.error(`❌ Filebase API error (attempt ${attempt}/${retries}):`);
        console.error(`   Status: ${statusCode}`);
        if (body) {
          try {
            const errorBody = JSON.parse(body);
            console.error(
              `   Message: ${errorBody.error?.details || errorBody.error?.reason || errorBody.message || body.substring(0, 200)}`,
            );
          } catch {
            console.error(`   Response: ${body.substring(0, 200)}`);
          }
        }

        if (statusCode === 401 || statusCode === 403) {
          console.error(
            "❌ Authentication failed - the pin token is base64(access_key:secret_key:bucket); check the Filebase credentials and bucket name",
          );
          process.exit(1);
        }
        if (statusCode >= 400 && statusCode < 500 && statusCode !== 429) {
          console.error("❌ Client error - not retrying");
          process.exit(1);
        }
      } else {
        console.error(
          `❌ Error (attempt ${attempt}/${retries}): ${error.message}`,
        );
      }

      if (isLastAttempt) {
        console.error(
          "❌ Failed to create Filebase pin after all retry attempts",
        );
        process.exit(1);
      }

      const waitTime = Math.min(1000 * Math.pow(2, attempt - 1), 10000);
      console.error(`⏳ Waiting ${waitTime}ms before retry...`);
      await new Promise((resolve) => setTimeout(resolve, waitTime));
    }
  }
}

async function findExistingPin() {
  try {
    const response = await client
      .get(`${API_BASE}/pins`, {
        searchParams: { cid, status: "queued,pinning,pinned" },
      })
      .json();
    const result = response?.results?.[0];
    if (result?.requestid) {
      return { requestid: result.requestid, status: result.status };
    }
  } catch (error) {
    console.error(`⚠️  Could not look up existing pin: ${error.message}`);
  }
  return null;
}

async function pollPin(requestid, initialStatus) {
  const deadline = Date.now() + PIN_TIMEOUT_MS;
  let status = initialStatus || "queued";

  while (status !== "pinned") {
    if (status === "failed") {
      console.error("❌ Filebase reported the pin as failed");
      done(requestid, status);
      process.exit(1);
    }
    if (Date.now() >= deadline) {
      // Best-effort: the content is already live on the primary provider and
      // Filebase keeps working on the pin server-side — warn, don't fail.
      console.error(
        `⚠️  Pin still '${status}' after ${PIN_TIMEOUT_MS}ms — Filebase continues pinning in the background (requestid: ${requestid})`,
      );
      done(requestid, status);
      return;
    }

    await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
    try {
      const response = await client.get(`${API_BASE}/pins/${requestid}`).json();
      status = response?.status || status;
      console.error(`⏳ Pin status: ${status}`);
    } catch (error) {
      console.error(`⚠️  Pin status check failed: ${error.message}`);
    }
  }

  console.error("✅ CID pinned on Filebase");
  done(requestid, status);
}

const pin = await createPin();
await pollPin(pin.requestid, pin.status);
