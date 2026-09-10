# IPFS Deployment

Deploys a **prebuilt** static site to IPFS via [Pinata](https://pinata.cloud) and/or [Filebase](https://filebase.com).

This is a composite action that runs inside the caller's job: point `build_dir` at the built site and the action uploads it, verifies gateway accessibility, writes a job summary and exposes the CID and gateway URLs as outputs. The built site can either already be on disk (build step in the same job) or come from a GitHub Actions artifact uploaded earlier in the run — pass `build_artifact_name` and the action downloads it into `build_dir` first. The uploader scripts, including their Node dependencies, ship with the action — nothing is fetched at runtime.

The site is always packed locally into a single-root CAR file (UnixFS, CIDv1), so the deployed CID is computed **before** any upload and is identical on every provider. The provider is selected by the credentials passed as inputs:

| `pinata_jwt` | Filebase inputs | Behavior                                                                                                 |
| ------------ | --------------- | -------------------------------------------------------------------------------------------------------- |
| set          | unset           | Uploads the CAR to Pinata via the v3 TUS upload API                                                      |
| unset        | set             | Uploads the CAR to Filebase via their S3-compatible API                                                  |
| set          | set             | Uploads the CAR to Filebase, then pins the already-known CID on Pinata via pin-by-CID (no second upload) |
| unset        | unset           | Fails validation                                                                                         |

The IPFS gateway list is owned by [`deploy-to-ipfs.sh`](./deploy-to-ipfs.sh) — it is assembled from the enabled providers' dedicated gateways (Filebase first when enabled, since it holds the full upload) plus the public `ipfs.io` and `dweb.link` gateways. The first entry is the primary gateway used for verification and reported as `ipfs_url`.

## Usage

Deploy to Pinata:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-node@v6
        with:
          node-version: 24
      - run: npm ci && npm run build
      - uses: hoprnet/hopr-workflows/actions/ipfs-deployment@ipfs-deployment-v1
        with:
          environment_name: prod
          project_name: my-app
          build_dir: out
          pinata_jwt: ${{ secrets.PINATA_JWT }}
```

Deploy a build artifact uploaded by an earlier job in the same run:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-node@v6
        with:
          node-version: 24
      - run: npm ci && npm run build
      - uses: actions/upload-artifact@v7
        with:
          name: site-build
          path: out
  deploy:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - uses: hoprnet/hopr-workflows/actions/ipfs-deployment@ipfs-deployment-v1
        with:
          environment_name: prod
          project_name: my-app
          build_artifact_name: site-build
          build_dir: out
          pinata_jwt: ${{ secrets.PINATA_JWT }}
```

Deploy to Filebase only:

```yaml
- uses: hoprnet/hopr-workflows/actions/ipfs-deployment@ipfs-deployment-v1
  with:
    environment_name: prod
    project_name: my-app
    build_dir: out
    filebase_access_key: ${{ secrets.FILEBASE_ACCESS_KEY }}
    filebase_secret_key: ${{ secrets.FILEBASE_SECRET_KEY }}
    filebase_bucket: my-app-prod
```

Deploy to Filebase and pin the CID on Pinata as a backup, then propose the new contenthash to ENS:

```yaml
- uses: hoprnet/hopr-workflows/actions/ipfs-deployment@ipfs-deployment-v1
  id: deploy
  with:
    environment_name: prod
    project_name: my-app
    build_dir: out
    pinata_jwt: ${{ secrets.PINATA_JWT }}
    filebase_access_key: ${{ secrets.FILEBASE_ACCESS_KEY }}
    filebase_secret_key: ${{ secrets.FILEBASE_SECRET_KEY }}
    filebase_bucket: my-app-prod
- uses: hoprnet/hopr-workflows/actions/propose-ens-contenthash@propose-ens-contenthash-v1
  with:
    cid: ${{ steps.deploy.outputs.ipfs_hash }}
    ens_name: my-app.example.eth
    # ...
```

## Inputs

| Name                         | Required | Default  | Description                                                                                            |
| ---------------------------- | -------- | -------- | ------------------------------------------------------------------------------------------------------ |
| `environment_name`           | Yes      | —        | Deployment environment name slug, must match `^[a-zA-Z0-9_-]+$` (e.g. `dev`, `staging`, `prod`)        |
| `project_name`               | Yes      | —        | Project name used for pin/upload metadata                                                              |
| `build_dir`                  | Yes      | —        | Directory containing the built site to deploy, relative to the workspace                               |
| `build_artifact_name`        | No       | `""`     | GitHub Actions artifact (uploaded earlier in the same run) to download into `build_dir` first          |
| `pinata_jwt`                 | No       | `""`     | Pinata JWT with the `org:files:write` and `org:files:read` scopes (paid plan required), enables Pinata |
| `filebase_access_key`        | No       | `""`     | Filebase S3 access key, enables the Filebase provider together with the other Filebase inputs          |
| `filebase_secret_key`        | No       | `""`     | Filebase S3 secret key belonging to `filebase_access_key`                                              |
| `filebase_bucket`            | No       | `""`     | Filebase bucket on the IPFS storage network, required when the Filebase keys are set                   |
| `upload_timeout_ms`          | No       | `300000` | Upload HTTP request timeout in milliseconds, must be `>= 10000`                                        |
| `pin_timeout_ms`             | No       | `600000` | How long to wait for the Pinata pin-by-CID to confirm before continuing with a warning, `>= 10000`     |
| `health_check`               | No       | `true`   | Run post-deploy gateway health checks before writing the job summary                                   |
| `upload_deployment_artifact` | No       | `true`   | Upload the `deployments/` metadata JSON as a run artifact                                              |
| `retention_days`             | No       | `30`     | Retention in days for the deployment metadata artifact                                                 |

At least one provider must be fully configured: `pinata_jwt`, and/or both Filebase keys together with `filebase_bucket`. Partial Filebase configuration (one key missing, or keys without a bucket) fails validation.

`environment` remains accepted as a deprecated alias for `environment_name` so existing callers keep working.

Pass the credential inputs from secrets (`pinata_jwt: ${{ secrets.PINATA_JWT }}`) so GitHub's log masking applies. Store them as organization secrets (**Settings → Secrets and variables → Actions**) restricted to the repositories that deploy.

## Outputs

| Name           | Description                                                                                                      |
| -------------- | ---------------------------------------------------------------------------------------------------------------- |
| `ipfs_hash`    | Deployed IPFS CID — always CIDv1 (`bafy…`), the locally computed CAR root                                        |
| `ipfs_url`     | Primary gateway URL for the deployed hash (the active provider's dedicated gateway)                              |
| `pinata_url`   | Dedicated Pinata gateway URL (`https://<gateway>/ipfs/<hash>/`), empty when Pinata is unused                     |
| `filebase_url` | Dedicated Filebase gateway URL (`https://gnosis-vpn.myfilebase.com/ipfs/<hash>/`), empty when Filebase is unused |

## Steps

1. **Download build artifact** _(when `build_artifact_name`)_ — downloads the named run artifact into `build_dir`
2. **Validate inputs** — rejects unsafe slugs and paths, out-of-range timeouts, and a missing or empty `build_dir`
3. **Detect providers** — decides which providers are configured from the credential inputs, rejects partial Filebase configuration
4. **Setup pnpm / Setup Node.js** — Node 24, pnpm 9
5. **Install uploader dependencies** — `pnpm install --frozen-lockfile` in the action directory
6. **Deploy to IPFS** — packs the site into a single-root CAR file, then uploads it with retries and exponential backoff: with both providers configured the CAR goes to Filebase and the CID is pinned on Pinata via pin-by-CID (waiting up to `pin_timeout_ms`, continuing with a warning if the pin is still propagating); with a single provider the CAR is uploaded to it directly. Each provider is verified to serve exactly the locally computed root CID, and `deployments/<environment>/latest.json` is written into the workspace
7. **Extract deployment info** — reads the CID and gateway URLs back out of the deployment JSON
8. **Upload deployment artifacts** _(when `upload_deployment_artifact`)_ — uploads `deployments/` as `deployment-<environment>-<sha>`
9. **Health check** _(when `health_check`)_ — probes every gateway, retrying up to three times; fails only if not a single gateway serves the content
10. **Summary** — writes the providers, access URLs and both CIDv0 and CIDv1 to the job summary

## Caller responsibilities

Because this is a composite action, job-level concerns stay with the caller:

- **Runner hardening** — when using `step-security/harden-runner` with a blocking egress policy, allow: `uploads.pinata.cloud` (Pinata CAR upload, Pinata-only mode), `api.pinata.cloud` (pin-by-CID and status polling), `s3.filebase.com` (Filebase upload), the pnpm registry, and the gateway hosts probed by the health check (`gnosis.mypinata.cloud`, `gnosis-vpn.myfilebase.com`, `ipfs.io`, `dweb.link`).
- **Timeout and concurrency** — set `timeout-minutes` on the job and a `concurrency` group if parallel deploys of the same environment must not overlap.

## Troubleshooting

| Symptom                                        | Cause and fix                                                                                                                                                                                                                                                                 |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Build directory 'out' not found`              | `build_dir` does not point at the build output — check the build step ran in the same job and wrote to that path, or pass `build_artifact_name` if the build ran in a different job                                                                                           |
| `Build directory is empty`                     | The build produced no files                                                                                                                                                                                                                                                   |
| `no IPFS provider configured`                  | Neither `pinata_jwt` nor the Filebase inputs were passed — check the `with:` block                                                                                                                                                                                            |
| `filebase_bucket is required`                  | The Filebase keys were passed without `filebase_bucket` (or vice versa)                                                                                                                                                                                                       |
| `401` / `403` from Pinata                      | `pinata_jwt` is invalid, expired, missing the `org:files:write` or `org:files:read` scope, or the account is on a free plan (CAR uploads and pin-by-CID require a paid plan) — regenerate the key on the [Pinata API keys page](https://app.pinata.cloud/developers/api-keys) |
| `Pinata pin still propagating`                 | A warning, not an error — the pin-by-CID request continues server-side at Pinata while Filebase already serves the content; raise `pin_timeout_ms` to wait longer, or just check the Pinata dashboard later                                                                   |
| Pin failed with terminal status                | `invalid_object` = the CID could not be retrieved as valid content; `over_free_limit`/`over_max_size` = Pinata plan limits; `expired`/`bad_host_node` = the content was not retrievable from the IPFS network in time                                                         |
| `SignatureDoesNotMatch` / `InvalidAccessKeyId` | The Filebase S3 credentials are wrong — check `filebase_access_key` and `filebase_secret_key`                                                                                                                                                                                 |
| `Uploaded object has no 'cid' metadata`        | The Filebase bucket is not on the IPFS storage network — CAR imports only work on IPFS buckets                                                                                                                                                                                |
| `returned CID …, expected the CAR root …`      | The provider re-interpreted the CAR instead of importing its root — the deploy fails safely instead of publishing a CID that does not match the providers                                                                                                                     |
| `Network error` / `ETIMEDOUT`                  | Uploads are retried with exponential backoff; for large sites raise `upload_timeout_ms` (Pinata uploads treat it as a stall timeout between progress events)                                                                                                                  |
| `Invalid or missing IPFS hash`                 | The provider returned an unexpected response — check the upload output in the logs and the provider's status page for rate limiting (429)                                                                                                                                     |

## Notes

- The uploaders never print credentials: script output is filtered for `jwt`, `token`, `secret`, `password`, `auth`, `bearer` and `authorization` before it reaches the log.
- `project_name` is sanitized to `[:alnum:]-_` (100 characters) before it is written to the deployment metadata.
- The site is packed **once, locally** into a single-root CAR file (UnixFS, CIDv1, raw leaves), so the deployed CID is known before any upload, is identical on every provider, and is reproducible for identical content. Each uploader verifies that its provider imported exactly that root CID and fails the deploy otherwise.
- Pinata imports the CAR via the v3 TUS upload API (`uploads.pinata.cloud`, resumable, ~50 MiB chunks) **only when it is the sole provider**. This requires a JWT with the `org:files:write` scope and a **paid** Pinata plan, and caps uploads at 25 GB (15 GB recommended). CAR validation on Pinata is asynchronous, so the CID can take a moment to become servable — the health check retries.
- When Filebase is configured alongside Pinata, Pinata instead pins the already-known CID via the v3 pin-by-CID API (`api.pinata.cloud`) and fetches the content from the IPFS network, where Filebase provides it. The pin request is asynchronous (queue statuses `prechecking` → `searching` → `retreiving`; `backfilled` means Pinata already had the content); the action polls for up to `pin_timeout_ms` and then **continues with a warning** if the pin is still propagating — the request stays active server-side, and only terminal failure statuses fail the deploy. Filebase's DHT announcement of fresh content can lag, so a pin that outlives the poll window is normal for large or brand-new deployments. Polling needs the `org:files:read` scope on the JWT.
- Filebase imports the CAR via the S3-compatible API (`s3.filebase.com`, `import=car`); the root CID is read back from the object's `x-amz-meta-cid` metadata. The bucket must be on Filebase's **IPFS storage network**.
- File size and request rate are subject to the providers' API limits.
