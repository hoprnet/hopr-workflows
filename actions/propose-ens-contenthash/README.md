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
          cid: ${{ needs.publish-ipfs.outputs.cid }}
          ens_name: ${{ vars.ENS_NAME }}
          resolver_address: "0x..."                              # ENS resolver holding the record
          safe_address: "0x..."                                  # Safe that owns the ENS name
          ens_delegate_private_key: ${{ secrets.ENS_DELEGATE_PRIVATE_KEY }}
          safe_api_key: ${{ secrets.SAFE_API_KEY }}              # required for Safe's hosted service
          rpc_url: ${{ secrets.RPC_URL }}                        # optional
```

## Requirements

- The `ens_delegate_private_key` address must already be registered as a **delegate** on the
  `safe_address` Safe (done once by a Safe owner — see
  [Safe delegates](https://docs.safe.global/core-api/transaction-service-guides/delegates)).
- The Safe must be the owner (or an approved operator) of the ENS name on the resolver.
- A **Safe Transaction Service API key** is required when using Safe's hosted service. Obtain one
  at <https://docs.safe.global/core-api/how-to-use-api-keys> and store it as `secrets.SAFE_API_KEY`.
  This is only optional if you point `safe_tx_service_url` at a self-hosted Transaction Service.

## Inputs

- `cid`: IPFS CID (CIDv0 or CIDv1) to set as the ENS contenthash. Required.
- `ens_name`: ENS name whose contenthash record is updated. Required.
- `resolver_address`: Address of the ENS resolver contract that holds the record. Required.
- `safe_address`: Address of the Safe multisig that owns the ENS name. Required.
- `ens_delegate_private_key`: Private key of the Safe delegate that proposes the transaction. Required.
- `safe_api_key`: Safe Transaction Service API key. Required for the hosted service; may be omitted
  only when `safe_tx_service_url` points at a self-hosted service. Default: empty.
- `rpc_url`: Ethereum mainnet RPC URL. When empty, viem's built-in mainnet public RPC is used.
  Default: empty.
- `safe_tx_service_url`: Custom Safe Transaction Service endpoint. When set, `safe_api_key` may be
  omitted. Default: empty (Safe's hosted mainnet service).

## Outputs

- `safe_tx_hash`: Hash of the proposed Safe transaction.
- `content_hash`: The encoded ENS contenthash (`0x…`) that was proposed.
- `namehash`: The ENS node hash of the name.
