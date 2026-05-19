# Cloudflare Manager

Central infrastructure-as-code repository for managing all Cloudflare resources via CLI and GitHub Actions.

## Architecture

```
cloudflare-manager/
├── workers/              # Cloudflare Workers (deployed via Wrangler)
│   ├── site-auth/        # Auth gateway for plot generator + OpenCode
│   ├── llm-proxy/        # LLM API proxy with server-side key injection
│   └── telemetry/        # Telemetry event collection
├── infrastructure/       # Declarative config for non-worker resources
│   ├── dns/              # DNS record definitions
│   ├── tunnels/          # Cloudflare Tunnel configurations
│   ├── access/           # Access applications and policies
│   ├── kv/               # KV namespace definitions
│   ├── r2/               # R2 bucket definitions
│   └── firewall/         # Firewall rules
├── scripts/              # Management scripts (PowerShell)
├── .github/workflows/    # CI/CD pipelines
└── secrets/              # Secret references (never actual secrets)
```

## Quick Start

### 1. Install dependencies

```bash
npm install
```

### 2. Configure authentication

Create a `.env` file (copy from `.env.example`):

```bash
cp .env.example .env
```

Set your Cloudflare API token. Create one at https://dash.cloudflare.com/profile/api-tokens with these permissions:
- **Workers** — Edit
- **DNS** — Edit
- **Access** — Edit
- **Account Settings** — Read
- **Zone** — Read (for madebysoupy.dev)

### 3. Deploy

```bash
# Deploy all workers
npm run deploy:all

# Sync DNS records
npm run sync:dns

# Sync Access policies
npm run sync:access

# Verify everything
npm run verify:all
```

## Workers

| Worker | Routes | Purpose |
|--------|--------|---------|
| `site-auth` | plots.\*, apps.madebysoupy.dev/plot_generator, opencode.\* | Auth gateway with Basic auth + session cookies |
| `llm-proxy` | llm-api.jscampbell21.workers.dev/\* | Proxies OpenAI/Claude API with server-side key injection |
| `telemetry` | telemetry.madebysoupy.dev/events | Collects telemetry events to Turso database |

## Infrastructure

### DNS

Defined in `infrastructure/dns/records.json`. Sync with:

```bash
npm run sync:dns
```

### Tunnels

Defined in `infrastructure/tunnels/*.yaml`. Applied locally on each machine:

```bash
npm run sync:tunnels
```

### Access

Defined in `infrastructure/access/*.json`. Sync with:

```bash
npm run sync:access
```

## GitHub Actions

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `deploy-workers.yml` | Push to `main` (workers/\*) | Auto-deploy workers |
| `sync-infra.yml` | Push to `main` (infrastructure/\*) | Sync DNS, Access, etc. |
| `verify.yml` | PR / non-main push | Validate configs, check for secrets |
| `health-check.yml` | Every 6 hours | Check endpoint reachability |

### Required Secrets

Set these in GitHub repository settings → Settings → Secrets and variables → Actions:

| Secret | Purpose |
|--------|---------|
| `CF_API_TOKEN` | Cloudflare API token |
| `CF_ACCOUNT_ID` | Cloudflare account ID |
| `CF_ZONE_ID` | Cloudflare zone ID (madebysoupy.dev) |

## Local Scripts

| Script | Purpose |
|--------|---------|
| `sync-dns.ps1` | Sync DNS records from config to Cloudflare |
| `sync-access.ps1` | Sync Access applications/policies |
| `sync-tunnels.ps1` | Generate cloudflared config files |
| `verify-all.ps1` | Comprehensive configuration verification |
| `health-check.ps1` | Quick endpoint reachability check |
| `secret-put.ps1` | Set Worker secrets interactively |
| `secret-list.ps1` | List expected secrets per worker |

## Security

- **Never commit secrets** — use `wrangler secret put`, GitHub Actions secrets, or `.env` (gitignored)
- **API tokens** — use scoped tokens with minimum required permissions
- **Service tokens** — store in GitHub Actions secrets, reference by name in config
- **Tunnel credentials** — stored locally, referenced by path in config

## Migration from Dashboard

This repo replaces manual Cloudflare dashboard configuration:

1. **Workers** — Source code + wrangler.toml in `workers/`
2. **DNS** — Declarative JSON in `infrastructure/dns/`
3. **Access** — Application definitions in `infrastructure/access/`
4. **Tunnels** — Config YAML in `infrastructure/tunnels/`
5. **Firewall** — Rules in `infrastructure/firewall/`

To migrate existing resources:
1. Export current config from dashboard
2. Create corresponding file in `infrastructure/`
3. Run sync script to verify
4. Commit to main

## Related Repos

- `llm-host` — Machine-specific Ollama/OpenCode operations
- `plot-generator` — Plot generator application (consumes these workers)
