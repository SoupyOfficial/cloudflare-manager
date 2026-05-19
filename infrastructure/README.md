# Infrastructure Configuration

This directory contains declarative configuration for all Cloudflare resources managed outside of Workers.

## Structure

- `dns/` — DNS record definitions
- `tunnels/` — Cloudflare Tunnel configurations
- `access/` — Access applications and policies
- `kv/` — KV namespace definitions
- `r2/` — R2 bucket definitions
- `firewall/` — Firewall rules and rate limiting

## Usage

These files are the source of truth. Use the scripts in `scripts/` to sync them to Cloudflare:

```bash
npm run sync:dns
npm run sync:access
npm run sync:tunnels
```

## Secrets

Actual secret values are never stored in this directory. Use:
- `wrangler secret put` for Worker secrets
- GitHub Actions secrets for CI/CD
- OS keychain or `.env` (gitignored) for local credentials
