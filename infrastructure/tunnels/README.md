# Tunnel Configurations

Each YAML file defines a Cloudflare Tunnel configuration.

## Structure

- `name` — Human-readable tunnel name
- `id` — Tunnel UUID (from `cloudflared tunnel info <name>`)
- `credentials_file_ref` — Path reference to credentials file (in secrets/)
- `ingress` — List of hostname → service mappings
- `machine` — Which machine hosts this ingress rule

## Syncing

Tunnel configs are applied locally on each machine:

```bash
# Windows
npm run sync:tunnels

# Or manually
cloudflared tunnel run ollama-home
```

## Machine Handoff

When switching a tunnel between machines:
1. Stop tunnel on current machine
2. Start tunnel on new machine
3. Verify with: npm run health