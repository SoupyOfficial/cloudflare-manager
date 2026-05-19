/**
 * LLM Proxy — Cloudflare Worker
 *
 * Purpose:
 * - Route /api/openai requests → inject OPENAI_API_KEY → forward to OpenAI
 * - Route /api/claude requests → inject CLAUDE_API_KEY → forward to Anthropic
 * - Route all other requests → add Cloudflare Access service-token headers → forward to private LLM host
 *
 * Required secrets (wrangler secret put):
 * - LLM_HOST_CLIENT_ID
 * - LLM_HOST_CLIENT_SECRET
 * - OPENAI_API_KEY (for /api/openai)
 * - CLAUDE_API_KEY (for /api/claude)
 *
 * Optional vars/secrets:
 * - LLM_UPSTREAM_URL (default: https://llm.madebysoupy.dev)
 * - ALLOWED_ORIGINS (comma-separated, default: https://apps.madebysoupy.dev)
 * - LLM_PROXY_TOKEN (optional Bearer token expected from browser)
 */

const DEFAULT_UPSTREAM = 'https://llm.madebysoupy.dev';
const DEFAULT_ALLOWED_ORIGINS = ['https://apps.madebysoupy.dev'];
const PASS_THROUGH_HEADERS = [
  'content-type',
  'accept',
  'cache-control',
  'pragma',
  'user-agent',
];

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin') || '';
    const allowedOrigins = parseAllowedOrigins(env.ALLOWED_ORIGINS);

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(origin, allowedOrigins),
      });
    }

    if (!['GET', 'POST'].includes(request.method)) {
      return jsonResponse({ error: 'Method not allowed' }, 405, origin, allowedOrigins);
    }

    if (origin && !isOriginAllowed(origin, allowedOrigins)) {
      return jsonResponse({ error: 'Origin not allowed' }, 403, origin, allowedOrigins);
    }

    const expectedProxyToken = env.LLM_PROXY_TOKEN;
    if (expectedProxyToken) {
      const authHeader = request.headers.get('Authorization') || '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
      if (!timingSafeEqual(token, expectedProxyToken)) {
        return jsonResponse({ error: 'Unauthorized' }, 401, origin, allowedOrigins);
      }
    }

    const incomingUrl = new URL(request.url);
    const pathname = incomingUrl.pathname;

    // Route cloud provider requests
    if (pathname === '/api/openai') {
      return handleOpenAiProxy(request, env, origin, allowedOrigins);
    }
    if (pathname === '/api/claude') {
      return handleClaudeProxy(request, env, origin, allowedOrigins);
    }

    // Default: route to novelist LLM via Cloudflare Access
    return handleNovelistProxy(request, env, origin, allowedOrigins, incomingUrl);
  },
};

/**
 * Handle /api/openai requests — inject OPENAI_API_KEY and forward to OpenAI
 */
async function handleOpenAiProxy(request, env, origin, allowedOrigins) {
  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Only POST allowed' }, 405, origin, allowedOrigins);
  }

  const apiKey = env.OPENAI_API_KEY;
  if (!apiKey) {
    return jsonResponse(
      { error: 'OpenAI API key not configured' },
      500,
      origin,
      allowedOrigins
    );
  }

  const forwardHeaders = new Headers();
  forwardHeaders.set('Authorization', `Bearer ${apiKey}`);
  forwardHeaders.set('Content-Type', 'application/json');
  forwardHeaders.set('User-Agent', request.headers.get('User-Agent') || 'plot-generator-llm-proxy');

  let body;
  try {
    body = await request.text();
  } catch (error) {
    return jsonResponse(
      { error: `Failed to read request body: ${error?.message}` },
      400,
      origin,
      allowedOrigins
    );
  }

  let upstreamResponse;
  try {
    upstreamResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: forwardHeaders,
      body,
    });
  } catch (error) {
    return jsonResponse(
      { error: `OpenAI request failed: ${error?.message || String(error)}` },
      502,
      origin,
      allowedOrigins
    );
  }

  const responseHeaders = new Headers(upstreamResponse.headers);
  applyCorsHeaders(responseHeaders, origin, allowedOrigins);
  responseHeaders.set('x-accel-buffering', 'no');
  responseHeaders.set('cache-control', 'no-store, no-cache');

  return new Response(upstreamResponse.body, {
    status: upstreamResponse.status,
    headers: responseHeaders,
  });
}

/**
 * Handle /api/claude requests — inject CLAUDE_API_KEY and forward to Anthropic
 */
async function handleClaudeProxy(request, env, origin, allowedOrigins) {
  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Only POST allowed' }, 405, origin, allowedOrigins);
  }

  const apiKey = env.CLAUDE_API_KEY;
  if (!apiKey) {
    return jsonResponse(
      { error: 'Claude API key not configured' },
      500,
      origin,
      allowedOrigins
    );
  }

  const forwardHeaders = new Headers();
  forwardHeaders.set('x-api-key', apiKey);
  forwardHeaders.set('Content-Type', 'application/json');
  forwardHeaders.set('anthropic-version', '2023-06-01');
  forwardHeaders.set('User-Agent', request.headers.get('User-Agent') || 'plot-generator-llm-proxy');

  let body;
  try {
    body = await request.text();
  } catch (error) {
    return jsonResponse(
      { error: `Failed to read request body: ${error?.message}` },
      400,
      origin,
      allowedOrigins
    );
  }

  let upstreamResponse;
  try {
    upstreamResponse = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: forwardHeaders,
      body,
    });
  } catch (error) {
    return jsonResponse(
      { error: `Claude request failed: ${error?.message || String(error)}` },
      502,
      origin,
      allowedOrigins
    );
  }

  const responseHeaders = new Headers(upstreamResponse.headers);
  applyCorsHeaders(responseHeaders, origin, allowedOrigins);
  responseHeaders.set('x-accel-buffering', 'no');
  responseHeaders.set('cache-control', 'no-store, no-cache');

  return new Response(upstreamResponse.body, {
    status: upstreamResponse.status,
    headers: responseHeaders,
  });
}

/**
 * Handle novelist LLM requests — add Cloudflare Access service-token headers
 */
async function handleNovelistProxy(request, env, origin, allowedOrigins, incomingUrl) {
  const clientId = env.LLM_HOST_CLIENT_ID;
  const clientSecret = env.LLM_HOST_CLIENT_SECRET;
  if (!clientId || !clientSecret) {
    return jsonResponse({ error: 'Proxy secrets not configured' }, 500, origin, allowedOrigins);
  }

  const upstreamBase = (env.LLM_UPSTREAM_URL || DEFAULT_UPSTREAM).replace(/\/+$/, '');
  const upstreamUrl = `${upstreamBase}${incomingUrl.pathname}${incomingUrl.search}`;

  const upstreamHeaders = new Headers();
  for (const header of PASS_THROUGH_HEADERS) {
    const value = request.headers.get(header);
    if (value) upstreamHeaders.set(header, value);
  }
  upstreamHeaders.set('CF-Access-Client-Id', clientId);
  upstreamHeaders.set('CF-Access-Client-Secret', clientSecret);
  // Prevent gzip/br compression on the upstream response so the streaming
  // body passes through the Worker unmodified.
  upstreamHeaders.set('Accept-Encoding', 'identity');

  let upstreamResponse;
  try {
    upstreamResponse = await fetch(upstreamUrl, {
      method: request.method,
      headers: upstreamHeaders,
      body: request.method === 'POST' ? request.body : undefined,
    });
  } catch (error) {
    return jsonResponse(
      { error: `Upstream request failed: ${error?.message || String(error)}` },
      502,
      origin,
      allowedOrigins
    );
  }

  const responseHeaders = new Headers(upstreamResponse.headers);
  applyCorsHeaders(responseHeaders, origin, allowedOrigins);
  responseHeaders.set('x-accel-buffering', 'no');
  responseHeaders.set('cache-control', 'no-store, no-cache');

  return new Response(upstreamResponse.body, {
    status: upstreamResponse.status,
    headers: responseHeaders,
  });
}

function parseAllowedOrigins(raw) {
  if (!raw || !String(raw).trim()) return DEFAULT_ALLOWED_ORIGINS;
  return String(raw)
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean);
}

function isOriginAllowed(origin, allowedOrigins) {
  if (!origin) return true;
  return allowedOrigins.includes(origin);
}

function applyCorsHeaders(headers, origin, allowedOrigins) {
  const allowOrigin = isOriginAllowed(origin, allowedOrigins)
    ? origin
    : allowedOrigins[0] || DEFAULT_ALLOWED_ORIGINS[0];
  headers.set('Access-Control-Allow-Origin', allowOrigin);
  headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  headers.set('Access-Control-Max-Age', '86400');
  headers.set('Vary', 'Origin');
}

function corsHeaders(origin, allowedOrigins) {
  const headers = new Headers();
  applyCorsHeaders(headers, origin, allowedOrigins);
  return headers;
}

function jsonResponse(payload, status, origin, allowedOrigins) {
  const headers = corsHeaders(origin, allowedOrigins);
  headers.set('Content-Type', 'application/json');
  return new Response(JSON.stringify(payload), { status, headers });
}

function timingSafeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}
