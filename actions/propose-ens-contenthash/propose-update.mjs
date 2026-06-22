// Encodes an IPFS CID as an ENS contenthash and proposes a `setContenthash`
// transaction to the Safe that owns the ENS name, signed by a Safe delegate.
// The delegate can only propose; Safe owners must confirm and execute.
import { appendFileSync } from 'node:fs'
import Safe from '@safe-global/protocol-kit'
import SafeApiKit from '@safe-global/api-kit'
import { namehash, encodeFunctionData, getAddress } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { mainnet } from 'viem/chains'
import { encode as encodeContentHash } from '@ensdomains/content-hash'

const required = (name) => {
  const value = process.env[name]
  if (!value) {
    console.error(`Missing required input: ${name}`)
    process.exit(1)
  }
  return value
}

const cid = required('CID')
const ensName = required('ENS_NAME')
const resolverAddress = getAddress(required('RESOLVER_ADDRESS'))
const safeAddress = getAddress(required('SAFE_ADDRESS'))
const privateKeyRaw = required('ENS_DELEGATE_PRIVATE_KEY')
const privateKey = privateKeyRaw.startsWith('0x') ? privateKeyRaw : `0x${privateKeyRaw}`
const rpcUrl = process.env.RPC_URL || mainnet.rpcUrls.default.http[0]
const txServiceUrl = process.env.SAFE_TX_SERVICE_URL || ''
const apiKey = process.env.SAFE_API_KEY || ''

if (!txServiceUrl && !apiKey) {
  console.error(
    'Missing SAFE_API_KEY: an API key is required when using the hosted Safe Transaction Service. ' +
      'Provide safe_api_key, or set safe_tx_service_url to a self-hosted Transaction Service.',
  )
  process.exit(1)
}

// 1. Encode the CID as an EIP-1577 ipfs contenthash. The library accepts both
// CIDv0 (Qm...) and CIDv1 (bafy...) and normalizes them to the same value.
const encoded = `0x${encodeContentHash('ipfs', cid)}`

// 2. Build the setContenthash calldata against the resolver.
const node = namehash(ensName)
const data = encodeFunctionData({
  abi: [
    {
      name: 'setContenthash',
      type: 'function',
      stateMutability: 'nonpayable',
      inputs: [
        { name: 'node', type: 'bytes32' },
        { name: 'hash', type: 'bytes' },
      ],
      outputs: [],
    },
  ],
  functionName: 'setContenthash',
  args: [node, encoded],
})

// 3. Build the Safe transaction, signed by the delegate key.
const protocolKit = await Safe.init({
  provider: rpcUrl,
  signer: privateKey,
  safeAddress,
})
const safeTransaction = await protocolKit.createTransaction({
  transactions: [{ to: resolverAddress, value: '0', data }],
})
const safeTxHash = await protocolKit.getTransactionHash(safeTransaction)
const signature = await protocolKit.signHash(safeTxHash)

// 4. Propose the transaction to the Safe Transaction Service as a delegate.
const apiKit = new SafeApiKit({
  chainId: 1n, // ENS lives only on mainnet
  ...(txServiceUrl ? { txServiceUrl } : {}),
  ...(apiKey ? { apiKey } : {}),
})
const senderAddress = privateKeyToAccount(privateKey).address
await apiKit.proposeTransaction({
  safeAddress,
  safeTransactionData: safeTransaction.data,
  safeTxHash,
  senderAddress,
  senderSignature: signature.data,
  origin: 'hopr-workflows/propose-ens-contenthash',
})

console.log(`Proposed setContenthash for ${ensName}`)
console.log(`  contenthash: ${encoded}`)
console.log(`  safeTxHash:  ${safeTxHash}`)

// 5. Emit outputs.
if (process.env.GITHUB_OUTPUT) {
  appendFileSync(
    process.env.GITHUB_OUTPUT,
    `safe_tx_hash=${safeTxHash}\ncontent_hash=${encoded}\nnamehash=${node}\n`,
  )
}
