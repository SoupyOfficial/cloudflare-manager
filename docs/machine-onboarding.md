# Machine Onboarding

How to add a new machine to the Cloudflare infrastructure.

## Prerequisites

1. Install cloudflared on the machine
2. Authenticate with Cloudflare: `cloudflared tunnel login`
3. Clone this repository

## Steps

### 1. Create Machine Config

Add a new file in `infrastructure/machines/`:

```yaml
# infrastructure/machines/<machine-name>.yaml
machine:
  name: <machine-name>
  os: windows | macos | linux
  hostname: <machine-hostname>
  services:
    - name: ollama
      port: 11434
    - name: opencode
      port: 4096
  tunnels:
    - name: <tunnel-name>
      config_file: <path-to-config>
```

### 2. Create or Assign Tunnel

Either:
- Create a new tunnel: `cloudflared tunnel create <name>`
- Or assign an existing tunnel to this machine

Update `infrastructure/tunnels/<tunnel-name>.yaml` with the machine assignment.

### 3. Generate Local Config

```bash
npm run sync:tunnels
```

This writes the cloudflared config to `~/.cloudflared/<tunnel-name>-config.yml`.

### 4. Start Tunnel

```bash
cloudflared tunnel run <tunnel-name>
```

### 5. Verify

```bash
npm run health-check
```

## Tunnel Handoff

When switching a tunnel between machines:

1. Stop tunnel on current machine
2. Start tunnel on new machine
3. Verify public hostname resolves to new origin
