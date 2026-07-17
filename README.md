# SustAInLivWork Annotation Tool

A self-hosted, rebranded fork of [CVAT](https://github.com/cvat-ai/cvat) (Computer Vision Annotation
Tool), tracking CVAT's `develop` branch.

This fork is meant to be built and hosted on your own premises. It is trimmed down accordingly: no
DICOM tooling, no Let's Encrypt HTTPS overlay, and no CI jobs that publish to registries we don't own.

Everything else is stock CVAT. For how to actually _use_ the annotation tool — tasks, jobs,
annotation formats, the API, automatic annotation — refer to the
[upstream CVAT documentation](https://docs.cvat.ai/docs/). It all applies here.

---

## Quick start

> **Read this first.** A plain `docker compose up` will **not** run this fork.
>
> CVAT's base `docker-compose.yml` has no `build:` section — it pulls the published `cvat/server`
> and `cvat/ui` images from Docker Hub. Run it on its own and you get **stock CVAT**, not your
> branding and not your changes. Building from source requires the `docker-compose.dev.yml` overlay,
> which is what supplies the `build:` sections.

Build the images from this source tree and start the stack:

```bash
./serverless.sh up --build
```

`serverless.sh` is the default launcher for this fork. It runs `docker compose` with the base file,
the dev overlay (which builds the branded images from source), and the Nuclio serverless overlay that
powers semi-automatic annotation. The first build takes a while. When it finishes, CVAT is on
**<http://localhost:8080>**.

Create an administrator:

```bash
./serverless.sh exec cvat_server \
    python3 /home/django/manage.py createsuperuser
```

Then sign in at <http://localhost:8080>.

Stop the stack (add `-v` to also delete the database volume — this destroys all users and
annotations):

```bash
./serverless.sh down
```

### Subsequent runs

Once the images are built and tagged locally, `./serverless.sh up` (no `--build`) starts what you
already built. Re-run with `--build` whenever you change the source.

To run **without** the AI subsystem — plain CVAT, no Nuclio — skip the launcher:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
```

### Ports

The base compose file binds only **8080** (the app) and **8090** (Traefik). The `docker-compose.dev.yml`
overlay additionally exposes Postgres (5432), Redis (6379, 6666), ClickHouse (8123), OPA (8181),
Vector (8282) and the worker debug ports (9090–9096). Use the overlay for building; you don't need
those ports published in production.

## Semi-automatic annotation

`./serverless.sh up` launches CVAT with the [Nuclio](https://nuclio.io/) serverless subsystem
enabled — the infrastructure CVAT uses for AI-assisted (semi-automatic) annotation such as
Segment Anything. The server runs with `CVAT_SERVERLESS=1`, so the AI-tools controls appear in the
annotation UI.

**No models are deployed by default.** The subsystem comes up empty: the AI-tools menu will show an
empty model list until you deploy a function. This is intentional — model images are large (several
GB each) and the interactive segmentation models expect a CUDA GPU, so deploying one is a deliberate,
separate step for when you have suitable hardware. To deploy a model, use CVAT's own tooling
(`serverless/deploy_gpu.sh` on a CUDA host, or `serverless/deploy_cpu.sh` for slow CPU inference) —
see the [upstream serverless tutorial](https://docs.cvat.ai/docs/manual/advanced/serverless-tutorial/).

> **Apple Silicon note:** Nuclio's dashboard image is `amd64`-only, so on an ARM Mac it runs under
> emulation — it starts, just slowly, and Docker may warn about the platform mismatch. On an
> `amd64` Linux host it runs natively.

## Deploying on-premises

### TLS

The upstream Traefik + Let's Encrypt (`docker-compose.https.yml`) overlay has been **removed**.
Traefik still fronts the app and serves plain HTTP on `:80`/`:8080`.

**Terminate TLS yourself**, with your own reverse proxy (nginx, Traefik, a load balancer, an ingress
controller) in front of CVAT. Do not expose the HTTP port directly to an untrusted network.

Set `CVAT_HOST` to the hostname users will reach the instance on — Traefik's routing rules and the
Grafana root URL both depend on it:

```bash
export CVAT_HOST=annotate.example.com
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
```

Because your proxy terminates TLS and forwards to Traefik over plain HTTP, Django must still be told
the public scheme is `https` — otherwise it builds `http://` upload (TUS) URLs that browsers block as
mixed content ([cvat-ai/cvat#4843](https://github.com/cvat-ai/cvat/issues/4843)). Set:

```bash
CVAT_PUBLIC_SCHEME=https
```

A Traefik middleware (`cvat-xfp` in `docker-compose.yml`) then forces `X-Forwarded-Proto` to that
value on every request. This is deliberate: the usual fix — trusting the proxy's IP via Traefik's
`forwardedHeaders.trustedIPs` — is unreliable under Docker Desktop, which rewrites the source address
of connections it proxies into the VM, so trust lists silently fail to match. Forcing the header
needs no trust at all, and is correct whenever the instance is only reachable over HTTPS. Leave the
variable unset for plain-HTTP localhost use.

### Expose via Cloudflare Tunnel

No inbound ports or TLS certificates needed — run a
[Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
(`cloudflared`) on the host and map a public hostname to CVAT:

1. In the Cloudflare Zero Trust dashboard, add a public hostname for your tunnel (e.g.
   `cvat.example.com`) pointing at **`http://localhost:8080`**.
2. Create a `.env` file next to `docker-compose.yml` (it is gitignored and read by
   `docker compose` automatically):

   ```bash
   CVAT_HOST=cvat.example.com
   CVAT_PUBLIC_SCHEME=https
   ```

3. Apply: `./serverless.sh up -d` (recreates only the affected containers; data is untouched).

CVAT is then live at `https://cvat.example.com`. Note that Traefik routes by hostname, so
`http://localhost:8080` returns **404** once `CVAT_HOST` is set — use the public URL.

## Branding

The branding assets are checked into the tree and used as-is — no build step is required. Three
assets carry the SustAInLivWork logo:

| Asset | Used for |
| --- | --- |
| `cvat/apps/engine/static/logo.svg` | App header — a one-line horizontal wordmark, derived by re-laying the source's three stacked lines onto a single baseline (the header slot is only 32px tall, where the stacked lockup would be illegible). Served via the `LOGO_FILENAME` Django setting. |
| `cvat-ui/src/assets/sustainlivwork-stacked.svg` | Login/register page — the full stacked lockup. |
| `cvat-ui/src/assets/favicon.svg` | Browser tab — the teal `AI` mark alone. |

Brand colours: black `#000000`, teal `#00B394`.

To replace the logo, edit these SVGs directly, or regenerate them from a new source PNG with the
checked-in `tools/branding/trace_logo.py` (see the comments in that script for the `SRC` and `BANDS`
settings). If you regenerate, keep the `class="brand-ink"` / `class="brand-teal"` attributes the
script emits: the login page stylesheet (`cvat-ui/src/components/signing-common/styles.scss`)
recolours the glyphs by selecting on `.brand-teal`, and dropping the class silently renders the teal
"AI" in the wrong colour with no build error.

## Staying current with upstream CVAT

This repo is a fork of `cvat-ai/cvat` and carries CVAT's full history, so upstream changes merge in
normally. Add the upstream remote once:

```bash
git remote add upstream https://github.com/cvat-ai/cvat.git
```

Then pull in new work:

```bash
git fetch upstream --tags
git merge upstream/develop   # or a release tag, e.g. `git merge v2.71.0`
```

Our changes are deliberately kept to small, isolated commits to keep that merge cheap. Expect
occasional conflicts in the files we touched: the CI workflows, the docs pages we pruned, and
`cvat-ui/src/components/signing-common/`.

## What was changed from upstream

| Area | Change |
| --- | --- |
| CI | Jobs requiring credentials this repo doesn't have are removed: Docker Hub publish, S3/Allure reports, Codecov, PyPI, and cvat.ai cross-repo triggers. Build, unit / REST / e2e / Helm tests and linters are all retained. |
| Branding | SustAInLivWork logo in the app header, on the login page, and as the favicon. Light login page. |
| Launcher | `serverless.sh` added as the default launcher: `docker compose` with the base file, the dev overlay, and the Nuclio serverless overlay. Upstream leaves you to compose the overlays by hand. |
| Proxy / TLS | A Traefik middleware (`cvat-xfp`) forces `X-Forwarded-Proto` to `CVAT_PUBLIC_SCHEME` (default `http`), so with `CVAT_PUBLIC_SCHEME=https` annotation (TUS) uploads work behind a TLS-terminating proxy or Cloudflare Tunnel ([cvat-ai/cvat#4843](https://github.com/cvat-ai/cvat/issues/4843)). Peer-IP trust was tested and does not work under Docker Desktop's source-address rewriting. |

## Licence & attribution

CVAT is developed by [CVAT.ai](https://www.cvat.ai/) and contributors, and is licensed under the
[MIT License](LICENSE). This fork inherits that licence. Upstream:
<https://github.com/cvat-ai/cvat>
