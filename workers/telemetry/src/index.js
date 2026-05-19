/**
 * CYOA Telemetry Collector — Cloudflare Worker
 *
 * Receives POST /events from the browser observability client and persists
 * each event to the app's existing Turso database via the Turso HTTP API.
 *
 * Expected request body:
 * {
 *   "source": "plot_generator",
 *   "scope": "cyoa",
 *   "sentAt": "<ISO timestamp>",
 *   "events": [ ...event objects ]
 * }
 *
 * Secrets required (set via `wrangler secret put`):
 *   - TURSO_URL        — e.g. libsql://your-database.turso.io
 *   - TURSO_AUTH_TOKEN — Turso auth token
 *   - TELEMETRY_TOKEN  — optional bearer-token for this endpoint
 *
 * Deploy:
 *   cd workers/telemetry
 *   wrangler deploy
 */

const ALLOWED_SOURCES = new Set(['plot_generator']);
const ALLOWED_SCOPES = new Set(['cyoa']);
const MAX_EVENTS_PER_BATCH = 500;

export default {
  async fetch(request, env) {
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return corsResponse(204, null, env);
    }

    if (request.method !== 'POST') {
      return corsResponse(405, { error: 'Method not allowed' }, env);
    }

    // Optional bearer-token auth.
    // If TELEMETRY_TOKEN is set, every request must include it.
    const expectedToken = env.TELEMETRY_TOKEN;
    if (expectedToken) {
      const authHeader = request.headers.get('Authorization') || '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
      if (!timingSafeEqual(token, expectedToken)) {
        return corsResponse(401, { error: 'Unauthorized' }, env);
      }
    }

    // Parse body
    let payload;
    try {
      payload = await request.json();
    } catch {
      return corsResponse(400, { error: 'Invalid JSON' }, env);
    }

    const { source, scope, sentAt, events } = payload ?? {};

    if (!ALLOWED_SOURCES.has(source)) {
      return corsResponse(400, { error: 'Unknown source' }, env);
    }
    if (!ALLOWED_SCOPES.has(scope)) {
      return corsResponse(400, { error: 'Unknown scope' }, env);
    }
    if (!Array.isArray(events) || events.length === 0) {
      return corsResponse(400, { error: 'events must be a non-empty array' }, env);
    }
    if (events.length > MAX_EVENTS_PER_BATCH) {
      return corsResponse(400, { error: `Too many events (max ${MAX_EVENTS_PER_BATCH})` }, env);
    }

    const receivedAt = new Date().toISOString();
    const ip = request.headers.get('CF-Connecting-IP') ?? null;

    // Build Turso HTTP API URL from libsql:// scheme → https://
    const tursoUrl = buildTursoHttpUrl(env.TURSO_URL);
    if (!tursoUrl) {
      console.error('[telemetry] TURSO_URL not configured');
      return corsResponse(500, { error: 'Storage not configured' }, env);
    }

    // Write all events in a single Turso pipeline request
    const requests = events.map((event) => {
      const {
        timestamp,
        type,
        name,
        traceId = null,
        spanId = null,
        sessionId = null,
        projectId = null,
        attrs = {},
        error = null,
      } = event ?? {};

      return {
        type: 'execute',
        stmt: {
          sql: `INSERT INTO cyoa_events
                  (source, scope, sent_at, received_at, event_type, event_name,
                   trace_id, span_id, session_id, project_id,
                   timestamp, attrs, error, ip)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          args: [
            { type: 'text', value: source },
            { type: 'text', value: scope },
            { type: sentAt ? 'text' : 'null', value: sentAt ?? null },
            { type: 'text', value: receivedAt },
            { type: type ? 'text' : 'null', value: type ?? null },
            { type: name ? 'text' : 'null', value: name ?? null },
            { type: traceId ? 'text' : 'null', value: traceId },
            { type: spanId ? 'text' : 'null', value: spanId },
            { type: sessionId ? 'text' : 'null', value: sessionId },
            { type: projectId ? 'text' : 'null', value: projectId },
            { type: timestamp ? 'text' : 'null', value: timestamp ?? null },
            { type: 'text', value: JSON.stringify(attrs) },
            { type: error ? 'text' : 'null', value: error ? JSON.stringify(error) : null },
            { type: ip ? 'text' : 'null', value: ip },
          ],
        },
      };
    });

    try {
      const tursoRes = await fetch(`${tursoUrl}/v2/pipeline`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${env.TURSO_AUTH_TOKEN}`,
        },
        body: JSON.stringify({ requests }),
      });

      if (!tursoRes.ok) {
        const text = await tursoRes.text().catch(() => '');
        console.error('[telemetry] Turso pipeline failed:', tursoRes.status, text);
        return corsResponse(500, { error: 'Storage error' }, env);
      }
    } catch (err) {
      console.error('[telemetry] Turso fetch failed:', err);
      return corsResponse(500, { error: 'Storage error' }, env);
    }

    return corsResponse(200, { accepted: events.length }, env);
  },
};

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Convert a libsql:// URL to the equivalent https:// Turso HTTP endpoint.
 * Handles both libsql:// and https:// inputs gracefully.
 */
function buildTursoHttpUrl(raw) {
  if (!raw) return null;
  return raw.replace(/^libsql:\/\//, 'https://').replace(/\/$/, '');
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Max-Age': '86400',
  };
}

function corsResponse(status, body, _env) {
  const headers = {
    ...corsHeaders(),
    'Content-Type': 'application/json',
  };
  return new Response(body ? JSON.stringify(body) : null, { status, headers });
}

/**
 * Constant-time string comparison to prevent timing attacks on the bearer token.
 */
function timingSafeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}
