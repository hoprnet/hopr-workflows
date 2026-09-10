#!/usr/bin/env node
// Convert an IPFS CID between v0 (base58btc "Qm...") and v1 (base32 "bafy...").
// Prints "cid_v0=<...>\ncid_v1=<...>" so callers can parse it.
//
// Usage: node cid-convert.mjs <cid>

import { CID } from "multiformats/cid";

const input = process.argv[2];
if (!input) {
  console.error("Usage: node cid-convert.mjs <cid>");
  process.exit(1);
}

// toV0() rejects anything that is not dag-pb + sha2-256, which is exactly the
// shape pack-car.mjs produces for the wrapping directory.
const cid = CID.parse(input);
process.stdout.write(`cid_v0=${cid.toV0()}\ncid_v1=${cid.toV1()}\n`);
