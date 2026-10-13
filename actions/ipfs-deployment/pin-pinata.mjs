// Pin an already-hosted CID on Pinata via the v3 pin-by-CID API, used when
// another provider (Filebase) received the CAR and serves the content: Pinata
// fetches it from the IPFS network instead of taking a second upload.
//
// The pin request is asynchronous on Pinata's side. The queue never reports a
// "pinned" status — a completed pin materializes as a file in the account's
// files list — so completion is detected by querying the files endpoint. If
// the pin does not complete within PIN_TIMEOUT_MS this script exits 0 with
// {pinned: false}: the request stays active server-side and the content is
// already served by the other provider, so a slow pin is a warning, not a
// deploy failure. Terminal queue statuses still fail hard.

const PINATA_JWT = process.env.PINATA_JWT;
const PIN_TIMEOUT_MS =
  Number.parseInt(process.env.PIN_TIMEOUT_MS || "", 10) || 600000;
// PINATA_API_ENDPOINT is an override for tests only.
const API =
  process.env.PINATA_API_ENDPOINT || "https://api.pinata.cloud/v3/files";
const POLL_INTERVAL_MS = 10000;
const REQUEST_TIMEOUT_MS = 30000;

const cid = process.argv[2];
const pinName = process.argv[3];

if (!PINATA_JWT || !cid || !pinName) {
  console.error(
    "❌ Usage: PINATA_JWT=<jwt> node pin-pinata.mjs <cid> <pin_name>",
  );
  process.exit(1);
}

// Queue statuses per the Pinata docs; "retreiving" is the documented spelling,
// accept the correct one too in case the API is ever fixed.
const IN_PROGRESS_STATUSES = new Set([
  "prechecking",
  "searching",
  "retreiving",
  "retrieving",
]);
const FAILED_STATUSES = new Set([
  "expired",
  "over_free_limit",
  "over_max_size",
  "invalid_object",
  "bad_host_node",
]);

function isRetryable(status) {
  if (status === 429 || (status >= 500 && status < 600)) return true;
  if (status >= 400 && status < 500) return false;
  // No HTTP status: network-level error (timeout, reset, DNS) — retry.
  return true;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function apiFetch(path, options = {}) {
  const response = await fetch(`${API}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${PINATA_JWT}`,
      ...(options.body ? { "Content-Type": "application/json" } : {}),
    },
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  const text = await response.text();
  let body = null;
  try {
    body = JSON.parse(text);
  } catch {
    // keep raw text for error reporting
  }
  if (!response.ok) {
    const error = new Error(
      `Pinata API ${options.method || "GET"} ${path} returned ${response.status}`,
    );
    error.status = response.status;
    error.body = text;
    throw error;
  }
  return body;
}

function failOnAuthError(error) {
  if (error.status === 401 || error.status === 403) {
    console.error(
      "❌ Authentication/authorization failed - pin-by-CID needs a JWT with the org:files:write and org:files:read scopes on a paid Pinata plan",
    );
    if (error.body) {
      console.error(`   Response: ${String(error.body).substring(0, 300)}`);
    }
    process.exit(1);
  }
}

// The account's files list is the source of truth for a completed pin.
async function findPinnedFile() {
  const body = await apiFetch(`/public?cid=${encodeURIComponent(cid)}&limit=1`);
  const files = body?.data?.files || [];
  return (
    files.find((file) => file?.cid?.toLowerCase() === cid.toLowerCase()) || null
  );
}

async function findQueueJob() {
  const body = await apiFetch(
    `/public/pin_by_cid?cid=${encodeURIComponent(cid)}&order=DESC&limit=10`,
  );
  const jobs = body?.data?.jobs || [];
  return (
    jobs.find((job) => job?.cid?.toLowerCase() === cid.toLowerCase()) || null
  );
}

function emitResult({ requestId, status, pinned }) {
  // Print only JSON (deploy scripts parse last line)
  console.log(
    JSON.stringify({
      cid,
      name: pinName,
      method: "pin_by_cid",
      request_id: requestId,
      status,
      pinned,
    }),
  );
}

async function submitPinRequest(retries = 3) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      console.error(
        `📌 Requesting Pinata pin-by-CID for ${cid} (attempt ${attempt}/${retries})...`,
      );
      const body = await apiFetch("/public/pin_by_cid", {
        method: "POST",
        body: JSON.stringify({ cid, name: pinName }),
      });
      const data = body?.data;
      if (data?.cid && data.cid.toLowerCase() !== cid.toLowerCase()) {
        console.error(`❌ Pinata queued CID ${data.cid}, expected ${cid}`);
        process.exit(1);
      }
      return data;
    } catch (error) {
      const isLastAttempt = attempt === retries;
      console.error(`❌ Pinata pin request error: ${error.message}`);
      failOnAuthError(error);

      if (error.status >= 400 && error.status < 500) {
        // Pinata rejects a duplicate pin request when the CID is already
        // pinned on the account — recheck the files list before failing.
        const existing = await findPinnedFile().catch(() => null);
        if (existing) {
          console.error("✅ CID is already pinned on Pinata");
          return { id: existing.id, already: true };
        }
        if (error.body) {
          console.error(`   Response: ${String(error.body).substring(0, 300)}`);
        }
        process.exit(1);
      }
      if (isLastAttempt) {
        console.error("❌ Failed to submit the pin request after all retries");
        process.exit(1);
      }

      const waitTime = Math.min(1000 * Math.pow(2, attempt - 1), 10000);
      console.error(`⏳ Waiting ${waitTime}ms before retry...`);
      await sleep(waitTime);
    }
  }
}

// Idempotency: a re-deploy of identical content produces the same CID, which
// may already be pinned from a previous run.
let alreadyPinned = null;
try {
  alreadyPinned = await findPinnedFile();
} catch (error) {
  failOnAuthError(error);
  console.error(
    `⚠️  Could not check existing pins (${error.message}), submitting a pin request anyway`,
  );
}
if (alreadyPinned) {
  console.error(`✅ CID ${cid} is already pinned on Pinata`);
  emitResult({
    requestId: alreadyPinned.id || null,
    status: "already_pinned",
    pinned: true,
  });
  process.exit(0);
}

const request = await submitPinRequest();
const requestId = request?.id || null;
if (request?.already) {
  emitResult({ requestId, status: "already_pinned", pinned: true });
  process.exit(0);
}

let lastStatus = request?.status || "queued";
console.error(
  `⏳ Pin request ${requestId || "(no id)"} queued (status: ${lastStatus}), waiting up to ${PIN_TIMEOUT_MS}ms...`,
);

const deadline = Date.now() + PIN_TIMEOUT_MS;
while (Date.now() < deadline) {
  await sleep(Math.min(POLL_INTERVAL_MS, Math.max(deadline - Date.now(), 1)));

  let file = null;
  let job = null;
  try {
    file = await findPinnedFile();
    if (!file) {
      job = await findQueueJob();
    }
  } catch (error) {
    failOnAuthError(error);
    if (!isRetryable(error.status)) {
      console.error(`❌ Pin status check failed: ${error.message}`);
      process.exit(1);
    }
    console.error(
      `⚠️  Pin status check failed (${error.message}), retrying...`,
    );
    continue;
  }

  if (file) {
    console.error(`✅ Pinata pinned ${cid}`);
    emitResult({ requestId, status: "pinned", pinned: true });
    process.exit(0);
  }

  if (job?.status) {
    if (job.status !== lastStatus) {
      console.error(`⏳ Pin status: ${lastStatus} → ${job.status}`);
      lastStatus = job.status;
    }
    if (job.status === "backfilled") {
      console.error(`✅ Pinata already had ${cid} (backfilled)`);
      emitResult({ requestId, status: "backfilled", pinned: true });
      process.exit(0);
    }
    if (FAILED_STATUSES.has(job.status)) {
      console.error(
        `❌ Pinata pin request failed with terminal status "${job.status}"`,
      );
      process.exit(1);
    }
    if (!IN_PROGRESS_STATUSES.has(job.status)) {
      console.error(
        `⚠️  Unknown pin status "${job.status}", continuing to wait`,
      );
    }
  }
  // Job missing and file absent: the queue and files list are eventually
  // consistent — keep polling until the deadline.
}

console.error(
  `⚠️  Pin request still in progress after ${PIN_TIMEOUT_MS}ms (last status: ${lastStatus})`,
);
console.error(
  "⚠️  The request continues server-side on Pinata; the content is already served by the primary provider",
);
emitResult({ requestId, status: lastStatus, pinned: false });
process.exit(0);
