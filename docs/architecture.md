# Architecture

## Overview

This repo is the single source of truth for all Cloudflare infrastructure. Everything that exists in the Cloudflare UI should be defined here.

## Resource Hierarchy

```
Account (b6ccd531a511f0021fa8d90c29cd5a3e)
├── Zone: madebysoupy.dev
│   ├── DNS Records
│   ├── Firewall Rules
│   └── Workers Routes
│       ├── plot-generator-site-auth
│       └── plot-generator-telemetry
├── Workers
│   ├── plot-generator-site-auth
│   ├── llm-api
│   └── plot-generator-telemetry
├── Access Applications
│   ├── LLM API (llm.madebysoupy.dev)
│   └── OpenCode IDE (opencode.madebysoupy.dev)
├── Tunnels
│   └── ollama-home
└── KV Namespaces
    └── (future)
```

## Auth Models

### 1. Cloudflare Access (Email/Service Token)

Used for: `llm.madebysoupy.dev`

- User authentication via email allowlist
- Server-to-server via Service Auth tokens
- Applied at Cloudflare edge before traffic reaches origin

### 2. Worker-Based Auth (Basic Auth + Sessions)

Used for: `opencode.madebysoupy.dev`, `apps.madebysoupy.dev`

- HTTP Basic authentication with session cookies
- Custom login portal at `plots.madebysoupy.dev`
- Implemented in `site-auth` worker

### 3. No Auth (Public)

Used for: `plots.madebysoupy.dev`

- GitHub Pages static site
- Publicly accessible

## Traffic Flow

### Plot Generator

```
Browser → apps.madebysoupy.dev/plot_generator
  → Cloudflare Edge
    → site-auth worker (auth check)
      → GitHub Pages (soupyofficial.github.io)
```

### OpenCode IDE

```
Browser → opencode.madebysoupy.dev
  → Cloudflare Edge
    → site-auth worker (auth check)
      → opencode-origin.madebysoupy.dev (tunnel)
        → Local OpenCode server (localhost:4096)
```

### LLM API

```
Browser/Server → llm.madebysoupy.dev
  → Cloudflare Edge
    → Access policy check (email or service token)
      → Cloudflare Tunnel
        → Local Ollama server (localhost:11434)
```

### LLM Proxy

```
Browser → llm-api.jscampbell21.workers.dev/api/openai
  → llm-proxy worker (injects API key)
    → OpenAI API
```

## Deployment Pipeline

```
Push to main
  → GitHub Actions
    → deploy-workers.yml (if workers/ changed)
      → wrangler deploy for each worker
    → sync-infra.yml (if infrastructure/ changed)
      → Sync DNS, Access, etc. via API
```

## Machine Responsibilities

### Windows PC
- Primary host for `ollama-home` tunnel
- Runs Ollama + OpenCode services
- Executes tunnel start/stop scripts

### Mac Mini
- Secondary host for `ollama-home` tunnel
- Runs Ollama service
- Can take over tunnel when Windows is offline

### GitHub Actions
- Deploys workers
- Syncs infrastructure config
- Runs health checks
