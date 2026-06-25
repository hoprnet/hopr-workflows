// Encodes an IPFS CID as an ENS contenthash and proposes a `setContenthash`
// transaction to the Safe that owns the ENS name, signed by a Safe delegate.

import { appendFileSync } from "node:fs";
import SafeApiKit from "@safe-global/api-kit";
import {
  namehash,
  encodeFunctionData,
  getAddress,
  hashDomain,
  hashStruct,
  hashTypedData,
  serializeSignature,
  zeroAddress,
} from "viem";
import { privateKeyToAccount, sign } from "viem/accounts";
import { encode as encodeContentHash } from "@ensdomains/content-hash";

const CHAIN_ID = 1;

// EIP-712 type of the Safe transaction struct (same across Safe >= 1.0.0).
const SAFE_TX_TYPES = {
  SafeTx: [
    { name: "to", type: "address" },
    { name: "value", type: "uint256" },
    { name: "data", type: "bytes" },
    { name: "operation", type: "uint8" },
    { name: "safeTxGas", type: "uint256" },
    { name: "baseGas", type: "uint256" },
    { name: "gasPrice", type: "uint256" },
    { name: "gasToken", type: "address" },
    { name: "refundReceiver", type: "address" },
    { name: "nonce", type: "uint256" },
  ],
};
const cid = process.env.cid;
const ensName = process.env.ens_name;
const resolverAddress = getAddress(process.env.resolver_address);
const safeAddress = getAddress(process.env.safe_address);
const privateKeyRaw = process.env.ens_delegate_private_key;
const privateKey = privateKeyRaw.startsWith("0x")
  ? privateKeyRaw
  : `0x${privateKeyRaw}`;
const txServiceUrl = process.env.safe_tx_service_url || "";
const origin =
  process.env.tx_origin || "hopr-workflows/propose-ens-contenthash";
const apiKey = process.env.safe_api_key || "";

// 1. Encode the CID as an EIP-1577 ipfs contenthash. The library accepts both
// CIDv0 (Qm...) and CIDv1 (bafy...) and normalizes them to the same value.
console.log(`Encoding CID ${cid} as an ipfs contenthash...`);
const encoded = `0x${encodeContentHash("ipfs", cid)}`;

// 2. Build the setContenthash calldata against the resolver.
console.log(`Building setContenthash calldata for ${ensName}...`);
const node = namehash(ensName);
const data = encodeFunctionData({
  abi: [
    {
      name: "setContenthash",
      type: "function",
      stateMutability: "nonpayable",
      inputs: [
        { name: "node", type: "bytes32" },
        { name: "hash", type: "bytes" },
      ],
      outputs: [],
    },
  ],
  functionName: "setContenthash",
  args: [node, encoded],
});

// 3. Read the Safe version and next nonce from the Transaction Service (no RPC).
// getNextNonce accounts for transactions already queued but not yet executed.
console.log(`Fetching Safe info and next nonce for ${safeAddress}...`);
const apiKit = new SafeApiKit({
  chainId: BigInt(CHAIN_ID),
  ...(txServiceUrl ? { txServiceUrl } : {}),
  ...(apiKey ? { apiKey } : {}),
});
const safeInfo = await apiKit.getSafeInfo(safeAddress);
const nonce = await apiKit.getNextNonce(safeAddress);
console.log(`  Safe version: ${safeInfo.version}, next nonce: ${nonce}`);

// 4. Compute the Safe EIP-712 transaction hash locally.
// Safe contracts >= 1.3.0 include chainId in the EIP-712 domain; older ones
// (which predate replay protection) use only the verifying contract.
console.log(`Computing the EIP-712 safeTxHash...`);
const includesChainId = atLeast130(safeInfo.version);
const domain = includesChainId
  ? { chainId: CHAIN_ID, verifyingContract: safeAddress }
  : { verifyingContract: safeAddress };
const eip712DomainType = includesChainId
  ? [
      { name: "chainId", type: "uint256" },
      { name: "verifyingContract", type: "address" },
    ]
  : [{ name: "verifyingContract", type: "address" }];

const safeTx = {
  to: resolverAddress,
  value: 0n,
  data,
  operation: 0, // CALL
  safeTxGas: 0n,
  baseGas: 0n,
  gasPrice: 0n,
  gasToken: zeroAddress,
  refundReceiver: zeroAddress,
  nonce: BigInt(nonce),
};

const safeTxHash = hashTypedData({
  domain,
  types: SAFE_TX_TYPES,
  primaryType: "SafeTx",
  message: safeTx,
});

// The Safe UI shows these EIP-712 components when an owner reviews the tx:
//   safeTxHash = keccak256(0x19 0x01 || domainHash || messageHash)
// Logging them lets a reviewer cross-check against what their wallet displays.
const domainHash = hashDomain({
  domain,
  types: { EIP712Domain: eip712DomainType },
});
const messageHash = hashStruct({
  data: safeTx,
  primaryType: "SafeTx",
  types: SAFE_TX_TYPES,
});

// 5. Sign the hash with the delegate key. Signing the digest directly yields an
// EIP-712 signature (v = 27/28), which is what the Safe contract expects.
const senderAddress = privateKeyToAccount(privateKey).address;
console.log(`Signing safeTxHash ${safeTxHash} as delegate ${senderAddress}...`);
const signature = serializeSignature(
  await sign({ hash: safeTxHash, privateKey }),
);

// 6. Propose the transaction to the Safe Transaction Service as a delegate.
console.log(`Proposing TX...`);
await apiKit.proposeTransaction({
  safeAddress,
  safeTransactionData: {
    to: resolverAddress,
    value: "0",
    data,
    operation: 0,
    safeTxGas: "0",
    baseGas: "0",
    gasPrice: "0",
    gasToken: zeroAddress,
    refundReceiver: zeroAddress,
    nonce: Number(nonce),
  },
  safeTxHash,
  senderAddress,
  senderSignature: signature,
  origin,
});

console.log(`Proposed setContenthash for ${ensName}`);
console.log(`  - Node / Namehash: ${node}`);
console.log(`  - Content hash: ${encoded}`);
console.log(`  - Domain hash:  ${domainHash}`);
console.log(`  - Message hash: ${messageHash}`);
console.log(`  - Safe TX hash:   ${safeTxHash}`);
console.log(`  - Data:         ${data}`);
console.log(
  `\nSafe queue url:    https://app.safe.global/transactions/queue?safe=eth:${safeAddress}`,
);

// 7. Emit outputs.
if (process.env.GITHUB_OUTPUT) {
  appendFileSync(
    process.env.GITHUB_OUTPUT,
    `safe_tx_hash=${safeTxHash}\n` +
      `content_hash=${encoded}\n` +
      `namehash=${node}\n` +
      `domain_hash=${domainHash}\n` +
      `message_hash=${messageHash}\n` +
      `data=${data}\n`,
  );
}

// Returns true when the Safe contract version is >= 1.3.0 (chainId in domain).
// Defaults to true for an unknown/missing version, matching modern deployments.
function atLeast130(version) {
  if (!version) return true;
  const [major = 0, minor = 0] = version.split(".").map((n) => Number(n));
  if (major !== 1) return major > 1;
  return minor >= 3;
}
