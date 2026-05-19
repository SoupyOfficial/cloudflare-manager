# Workers

All Cloudflare Workers are managed from this directory.

## Structure

Each worker has its own subdirectory with:
- `wrangler.toml` — Worker configuration (routes, bindings, vars)
- `src/` — Source code
- `.dev.vars` — Local development variables (gitignored)

## Workers

| Worker | Name | Routes | Purpose |
|--------|------|--------|---------|
| `site-auth/` | `plot-generator-site-auth` | plots.*, apps.madebysoupy.dev/plot_generator, opencode.* | Auth gateway for plot generator and OpenCode |
| `llm-proxy/` | `llm-api` | llm-api.jscampbell21.workers.dev/* | LLM API proxy with server-side key injection |
| `telemetry/` | `plot-generator-telemetry` | telemetry.madebysoupy.dev/events | Telemetry event collection |

## Deployment

```bash
# Deploy all workers
npm run deploy:all

# Deploy individual worker
npm run deploy:site-auth
npm run deploy:llm-proxy
npm run deploy:telemetry

# Local development
npm run dev:site-auth
npm run dev:llm-proxy
npm run dev:telemetry
```

## Secrets

Set secrets using wrangler CLI:
```bash
cd workers/<worker-name>
wrangler secret put SECRET_NAME
```

Never commit secret values to this repository.
