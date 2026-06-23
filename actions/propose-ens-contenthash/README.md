# Propose ENS Contenthash

This action takes an IPFS CID (e.g. produced by a previous workflow that publishes to IPFS),
encodes it as an [EIP-1577](https://eips.ethereum.org/EIPS/eip-1577) `ipfs` contenthash, and
**proposes** a `setContenthash` transaction to the [Safe](https://safe.global) multisig that owns
the ENS name. The proposal is signed by a **Safe delegate** (`ENS_DELEGATE_PRIVATE_KEY`).

## Usage

```yaml
- name: Update ENS contenthash
  uses: hoprnet/hopr-workflows/actions/propose-ens-contenthash@propose-ens-contenthash-v1
  with:
    CID: ${{ needs.publish-ipfs.outputs.cid }}
    ENS_NAME: ${{ vars.ENS_NAME }}
    RESOLVER_ADDRESS: "0x..." # ENS resolver holding the record
    SAFE_ADDRESS: "0x..." # Safe that owns the ENS name
    ENS_DELEGATE_PRIVATE_KEY: ${{ secrets.ENS_DELEGATE_PRIVATE_KEY }}
    SAFE_API_KEY: ${{ secrets.SAFE_API_KEY }} # required for Safe's hosted service
```

## Requirements

- The `ENS_DELEGATE_PRIVATE_KEY` address must already be registered as a **delegate** on the
  `SAFE_ADDRESS` Safe (done once by a Safe owner — see
  [Safe delegates](https://docs.safe.global/core-api/transaction-service-guides/delegates)).
- The Safe must be the owner (or an approved operator) of the ENS name on the resolver.
- A **Safe Transaction Service API key** is required when using Safe's hosted service. Obtain one
  at <https://docs.safe.global/core-api/how-to-use-api-keys> and store it as `secrets.SAFE_API_KEY`.
  This is only optional if you point `safe_tx_service_url` at a self-hosted Transaction Service.

## Inputs

- `CID`: IPFS CID (CIDv0 or CIDv1) to set as the ENS contenthash. Required.
- `ENS_NAME`: ENS name whose contenthash record is updated. Required.
- `RESOLVER_ADDRESS`: Address of the ENS resolver contract that holds the record. Required.
- `SAFE_ADDRESS`: Address of the Safe multisig that owns the ENS name. Required.
- `ENS_DELEGATE_PRIVATE_KEY`: Private key of the Safe delegate that proposes the transaction. Required.
- `SAFE_API_KEY`: Safe Transaction Service API key. Required for the hosted service; may be omitted
  only when `SAFE_TX_SERVICE_URL` points at a self-hosted service. Default: empty.
- `SAFE_TX_SERVICE_URL`: Custom Safe Transaction Service endpoint. When set, `SAFE_API_KEY` may be
  omitted. Default: empty (Safe's hosted mainnet service).
- `TX_ORIGIN`: Free-text origin label attached to the proposed transaction (shown in the Safe UI).
  Default: `hopr-workflows/propose-ens-contenthash`.

## Outputs

- `safe_tx_hash`: Hash of the proposed Safe transaction.
- `content_hash`: The encoded ENS contenthash (`0x…`) that was proposed.
- `namehash`: The ENS node hash of the name.
- `domain_hash`: EIP-712 domain hash of the Safe transaction (as shown in the Safe UI).
- `message_hash`: EIP-712 message hash of the Safe transaction (as shown in the Safe UI).
- `data`: The `setContenthash` calldata sent to the resolver.
