# Infrastructure Configuration

This directory contains declarative configuration for all Cloudflare resources managed outside of Workers.

## Structure

- `dns/` — DNS record definitions
- `tunnels/` — Cloudflare Tunnel configurations
- `access/` — Access applications and policies
- `kv/` — KV namespace definitions
- `r2/` — R2 bucket definitions
- `firewall/` — WAF custom rules and firewall policies

## Usage

These files are the source of truth. Use the scripts in `scripts/` to sync them to Cloudflare:

```bash
npm run sync:dns
npm run sync:access
npm run sync:tunnels
npm run sync:firewall
```

## Firewall Rules

WAF custom rules are defined in `firewall/rules.json` and deployed via the Cloudflare Rulesets API (`http_request_firewall_custom` phase). The current rules include:

- **Allow health check bot** — Skips Bot Fight Mode and Security Level for requests with `User-Agent: HealthCheckBot/1.0`, enabling GitHub Actions health checks to pass Cloudflare's edge.
- **Block known bad bots** — Blocks requests matching known bad bot patterns.
- **Rate limit API endpoints** — Managed challenge for `/api/` paths (disabled by default).

## Secrets

Actual secret values are never stored in this directory. Use:
- `wrangler secret put` for Worker secrets
- GitHub Actions secrets for CI/CD
- OS keychain or `.env` (gitignored) for local credentials
