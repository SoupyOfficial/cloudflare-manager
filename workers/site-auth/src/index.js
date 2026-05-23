/**
 * Site Auth Gateway — Cloudflare Worker
 *
 * Minimal protection for a static app using HTTP Basic auth at the edge.
 * If credentials are valid, apps.* requests are proxied to the configured upstream.
 * plots.* is used only as a login portal and always redirects back to apps.*.
 *
 * Required secrets (set with `wrangler secret put`):
 * - BASIC_AUTH_USERNAME
 * - BASIC_AUTH_PASSWORD
 *
 * Optional vars:
 * - UPSTREAM_URL (default: https://soupyofficial.github.io/plot_generator/)
 * - LOGIN_URL (default: https://plots.madebysoupy.dev/)
 * - OPENCODE_UPSTREAM_URL (default: https://opencode-origin.madebysoupy.dev/)
 * - OPENCODE_WS_UPSTREAM_URL (default: https://opencode-ws.madebysoupy.dev/)
 */

const DEFAULT_UPSTREAM_URL = 'https://soupyofficial.github.io/plot_generator/'
const DEFAULT_OPENCODE_UPSTREAM_URL = 'https://opencode-origin.madebysoupy.dev/'
const DEFAULT_LOGIN_URL = 'https://plots.madebysoupy.dev/'
const APPS_BASE_PATH = '/plot_generator'
// Host names are env-overridable so the same worker code handles both prod and test
// environments. Override via APPS_HOST / PLOTS_HOST / OPENCODE_HOST vars in wrangler.toml.
const DEFAULT_APPS_HOST = 'apps.madebysoupy.dev'
const DEFAULT_PLOTS_HOST = 'plots.madebysoupy.dev'
const DEFAULT_OPENCODE_HOST = 'opencode.madebysoupy.dev'
const REALM = 'Plot Generator'
const SESSION_COOKIE_NAME = 'pg_auth'
const SESSION_MAX_AGE_SECONDS = 60 * 60 * 12
const OPENCODE_PUBLIC_PATHS = new Set(['/site.webmanifest'])
const CSP_UNSAFE_INLINE = "'unsafe-inline'"
const CLOUDFLARE_INSIGHTS_SCRIPT_SRC = 'https://static.cloudflareinsights.com'
const DEFAULT_OPENCODE_WS_UPSTREAM_URL = 'https://opencode-ws.madebysoupy.dev/'

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204 })
    }

    const APPS_HOST = env.APPS_HOST || DEFAULT_APPS_HOST
    const PLOTS_HOST = env.PLOTS_HOST || DEFAULT_PLOTS_HOST
    const OPENCODE_HOST = env.OPENCODE_HOST || DEFAULT_OPENCODE_HOST

    const incomingUrl = new URL(request.url)
    const isAppsHost = incomingUrl.hostname === APPS_HOST
    const isPlotsHost = incomingUrl.hostname === PLOTS_HOST
    const isOpencodeHost = incomingUrl.hostname === OPENCODE_HOST

    const expectedUser = env.BASIC_AUTH_USERNAME
    const expectedPass = env.BASIC_AUTH_PASSWORD

    if (!expectedUser || !expectedPass) {
      return new Response('Auth gateway is not configured', { status: 500 })
    }

    const credentials = parseBasicAuth(request.headers.get('Authorization'))
    const isBasicAllowed =
      credentials &&
      timingSafeEqual(credentials.username, expectedUser) &&
      timingSafeEqual(credentials.password, expectedPass)
    const hasValidSession = await isSessionAllowed(request, expectedUser, expectedPass)
    const isAllowed = isBasicAllowed || hasValidSession

    if (!isAllowed) {
      if (isOpencodeHost && isOpencodePublicAssetRequest(request, incomingUrl)) {
        const publicAssetUrl = buildTargetUrl(
          env.OPENCODE_UPSTREAM_URL || DEFAULT_OPENCODE_UPSTREAM_URL,
          incomingUrl,
        )
        const publicAssetRequest = new Request(publicAssetUrl.toString(), request)
        return fetch(publicAssetRequest, { redirect: 'manual' })
      }

      // Top-level document requests to apps/opencode are redirected to plots.*
      // before any content loads. Non-document requests return 401 so assets
      // do not cross-origin redirect to the login host (which causes CSP noise).
      if (isAppsHost || isOpencodeHost) {
        if (isDocumentNavigationRequest(request)) {
          const loginUrl = buildLoginRedirectUrl(env.LOGIN_URL || DEFAULT_LOGIN_URL, incomingUrl)
          return new Response(null, {
            status: 302,
            headers: {
              Location: loginUrl,
              'Cache-Control': 'no-store',
            },
          })
        }

        return new Response('Authentication required', {
          status: 401,
          headers: {
            'Cache-Control': 'no-store',
          },
        })
      }

      // On plots.*, trigger browser auth prompt directly.
      if (isPlotsHost) {
        return new Response('Authentication required', {
          status: 401,
          headers: {
            'WWW-Authenticate': `Basic realm="${REALM}", charset="UTF-8"`,
            'Cache-Control': 'no-store',
          },
        })
      }

      return new Response('Unauthorized', { status: 401 })
    }

    if (isPlotsHost) {
      const returnTo = incomingUrl.searchParams.get('return_to')
      const redirectTarget = isSafeReturnTo(returnTo, APPS_HOST, OPENCODE_HOST)
        ? returnTo
        : buildAppsRedirectUrl(incomingUrl, APPS_HOST)
      const redirectHeaders = new Headers({
        Location: redirectTarget,
        'Cache-Control': 'no-store',
      })
      if (isBasicAllowed) {
        redirectHeaders.append(
          'Set-Cookie',
          await buildSessionCookie(expectedUser, expectedPass),
        )
      }

      return new Response(null, {
        status: 302,
        headers: redirectHeaders,
      })
    }

    const upstreamBase = isOpencodeHost
      ? (env.OPENCODE_UPSTREAM_URL || DEFAULT_OPENCODE_UPSTREAM_URL)
      : (env.UPSTREAM_URL || DEFAULT_UPSTREAM_URL)

    // Cloudflare Workers support WebSocket proxying via fetch().
    // WS upgrades for opencode are routed through opencode-ws (proxied=true tunnel endpoint)
    // rather than opencode-origin (proxied=false) so Cloudflare edge handles the upgrade correctly.
    // Do NOT pass redirect:'manual' for WebSocket — the runtime pipes the connection.
    const isWebSocketUpgrade = request.headers.get('Upgrade') === 'websocket'
    if (isWebSocketUpgrade) {
      if (!isOpencodeHost) {
        return new Response('WebSocket not supported on this host', {
          status: 502,
          headers: { 'Content-Type': 'text/plain' },
        })
      }
      const wsUpstreamBase = env.OPENCODE_WS_UPSTREAM_URL || DEFAULT_OPENCODE_WS_UPSTREAM_URL
      const wsTargetUrl = buildTargetUrl(wsUpstreamBase, incomingUrl)
      const wsRequest = new Request(wsTargetUrl.toString(), request)
      wsRequest.headers.set(
        'Authorization',
        `Basic ${btoa(`${expectedUser}:${expectedPass}`)}`,
      )
      return fetch(wsRequest)
    }

    const targetUrl = buildTargetUrl(upstreamBase, incomingUrl, {
      stripPrefix: isAppsHost ? APPS_BASE_PATH : '',
    })

    const proxiedRequest = new Request(targetUrl.toString(), request)
    if (isOpencodeHost) {
      // The OpenCode origin requires HTTP Basic auth. The browser authenticates
      // via the pg_auth session cookie, so we inject the upstream credentials
      // here to satisfy the origin server regardless of how the browser authed.
      proxiedRequest.headers.set(
        'Authorization',
        `Basic ${btoa(`${expectedUser}:${expectedPass}`)}`,
      )
    }
    const upstreamResponse = await fetch(proxiedRequest, { redirect: 'manual' })

    const responseHeaders = new Headers(upstreamResponse.headers)
    const location = responseHeaders.get('Location')
    if (location) {
      const rewritten = rewriteUpstreamLocation(location, {
        incomingUrl,
        targetUrl,
        isAppsHost,
      })
      responseHeaders.set('Location', rewritten)
    }

    if (isOpencodeHost) {
      patchOpencodeResponseCsp(responseHeaders)
    }

    if (isBasicAllowed) {
      responseHeaders.append('Set-Cookie', await buildSessionCookie(expectedUser, expectedPass))
    }

    return new Response(upstreamResponse.body, {
      status: upstreamResponse.status,
      statusText: upstreamResponse.statusText,
      headers: responseHeaders,
    })
  },
}

function isDocumentNavigationRequest(request) {
  const secFetchDest = request.headers.get('sec-fetch-dest') || ''
  const secFetchMode = request.headers.get('sec-fetch-mode') || ''
  const accept = request.headers.get('accept') || ''

  if (secFetchDest.toLowerCase() === 'document') return true
  if (secFetchMode.toLowerCase() === 'navigate') return true
  return accept.toLowerCase().includes('text/html')
}

function isOpencodePublicAssetRequest(request, incomingUrl) {
  if (request.method !== 'GET' && request.method !== 'HEAD') return false
  return OPENCODE_PUBLIC_PATHS.has(incomingUrl.pathname)
}

function patchOpencodeResponseCsp(headers) {
  const contentType = headers.get('Content-Type') || ''
  if (!contentType.toLowerCase().includes('text/html')) return

  const csp = headers.get('Content-Security-Policy')
  if (!csp) return

  let patched = stripScriptSrcHashes(csp)
  patched = withScriptSrcToken(patched, CLOUDFLARE_INSIGHTS_SCRIPT_SRC)
  patched = withScriptSrcToken(patched, CSP_UNSAFE_INLINE)
  headers.set('Content-Security-Policy', patched)
}

function stripScriptSrcHashes(csp) {
  const directives = csp
    .split(';')
    .map((part) => part.trim())
    .filter(Boolean)

  const scriptSrcIndex = directives.findIndex((directive) => directive.startsWith('script-src'))
  if (scriptSrcIndex === -1) return directives.join('; ')

  const scriptParts = directives[scriptSrcIndex].split(/\s+/)
  const filtered = scriptParts.filter(
    (part, index) => index === 0 || !/^'sha(256|384|512)-/.test(part),
  )
  directives[scriptSrcIndex] = filtered.join(' ')

  return directives.join('; ')
}

function withScriptSrcToken(csp, token) {
  const directives = csp
    .split(';')
    .map((part) => part.trim())
    .filter(Boolean)

  const scriptSrcIndex = directives.findIndex((directive) => directive.startsWith('script-src'))
  if (scriptSrcIndex === -1) {
    directives.push(`script-src ${token}`)
    return directives.join('; ')
  }

  const scriptParts = directives[scriptSrcIndex].split(/\s+/)
  if (!scriptParts.includes(token)) {
    scriptParts.push(token)
    directives[scriptSrcIndex] = scriptParts.join(' ')
  }

  return directives.join('; ')
}

function parseBasicAuth(authHeader) {
  if (!authHeader || !authHeader.startsWith('Basic ')) return null

  try {
    const decoded = atob(authHeader.slice(6))
    const separatorIndex = decoded.indexOf(':')
    if (separatorIndex < 0) return null

    return {
      username: decoded.slice(0, separatorIndex),
      password: decoded.slice(separatorIndex + 1),
    }
  } catch {
    return null
  }
}

function buildTargetUrl(upstreamBase, incomingUrl, options = {}) {
  const { stripPrefix = '' } = options
  const upstream = new URL(upstreamBase)
  const basePath = upstream.pathname.endsWith('/')
    ? upstream.pathname.slice(0, -1)
    : upstream.pathname

  let requestPath = incomingUrl.pathname
  if (stripPrefix && requestPath.startsWith(stripPrefix)) {
    requestPath = requestPath.slice(stripPrefix.length) || '/'
  }
  // Keep root requests as '/' so upstream path becomes '/plot_generator/'
  // instead of '/plot_generator' (which can trigger an origin redirect).
  if (!requestPath.startsWith('/')) {
    requestPath = `/${requestPath}`
  }

  upstream.pathname = `${basePath}${requestPath}` || '/'
  upstream.search = incomingUrl.search

  return upstream
}

function buildLoginRedirectUrl(baseLoginUrl, incomingUrl) {
  const target = new URL(baseLoginUrl)
  let path = incomingUrl.pathname
  if (path.startsWith(APPS_BASE_PATH)) {
    path = path.slice(APPS_BASE_PATH.length) || '/'
  }
  target.pathname = path
  target.search = incomingUrl.search
  target.searchParams.set('return_to', incomingUrl.toString())
  return target.toString()
}

function buildAppsRedirectUrl(incomingUrl, appsHost) {
  const target = new URL(`https://${appsHost}${APPS_BASE_PATH}`)
  const normalizedPath = incomingUrl.pathname === '/' ? '' : incomingUrl.pathname
  target.pathname = `${APPS_BASE_PATH}${normalizedPath}`

  const searchParams = new URLSearchParams(incomingUrl.search)
  searchParams.delete('return_to')
  const nextSearch = searchParams.toString()
  target.search = nextSearch ? `?${nextSearch}` : ''
  target.hash = incomingUrl.hash

  return target.toString()
}

async function isSessionAllowed(request, expectedUser, expectedPass) {
  const cookies = parseCookies(request.headers.get('Cookie'))
  const token = cookies[SESSION_COOKIE_NAME]
  if (!token) return false

  const dotIndex = token.indexOf('.')
  if (dotIndex <= 0 || dotIndex >= token.length - 1) return false

  const expiresAtRaw = token.slice(0, dotIndex)
  const signature = token.slice(dotIndex + 1)
  if (!/^\d+$/.test(expiresAtRaw)) return false

  const expiresAt = Number(expiresAtRaw)
  if (!Number.isFinite(expiresAt) || Date.now() > expiresAt) return false

  const expectedSignature = await signSession(expiresAtRaw, expectedUser, expectedPass)
  return timingSafeEqual(signature, expectedSignature)
}

async function buildSessionCookie(expectedUser, expectedPass) {
  const expiresAt = Date.now() + SESSION_MAX_AGE_SECONDS * 1000
  const expiresAtRaw = String(expiresAt)
  const signature = await signSession(expiresAtRaw, expectedUser, expectedPass)
  const value = `${expiresAtRaw}.${signature}`

  return `${SESSION_COOKIE_NAME}=${value}; Max-Age=${SESSION_MAX_AGE_SECONDS}; Domain=.madebysoupy.dev; Path=/; HttpOnly; Secure; SameSite=Lax`
}

function isSafeReturnTo(returnTo, appsHost, opencodeHost) {
  if (!returnTo) return false

  try {
    const url = new URL(returnTo)
    if (url.hostname === appsHost) {
      return url.pathname.startsWith(APPS_BASE_PATH)
    }

    if (url.hostname === opencodeHost) {
      return true
    }

    return false
  } catch {
    return false
  }
}

function parseCookies(cookieHeader) {
  if (!cookieHeader) return {}

  return cookieHeader
    .split(';')
    .map((entry) => entry.trim())
    .filter(Boolean)
    .reduce((acc, entry) => {
      const eqIndex = entry.indexOf('=')
      if (eqIndex <= 0) return acc
      const key = entry.slice(0, eqIndex)
      const value = entry.slice(eqIndex + 1)
      acc[key] = value
      return acc
    }, {})
}

async function signSession(expiresAtRaw, expectedUser, expectedPass) {
  const encoder = new TextEncoder()
  const keyMaterial = encoder.encode(`${expectedUser}:${expectedPass}`)
  const data = encoder.encode(`pg-auth:${expiresAtRaw}`)

  const key = await crypto.subtle.importKey(
    'raw',
    keyMaterial,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const signature = await crypto.subtle.sign('HMAC', key, data)
  return base64UrlEncode(signature)
}

function base64UrlEncode(buffer) {
  const bytes = new Uint8Array(buffer)
  let binary = ''
  for (const byte of bytes) {
    binary += String.fromCharCode(byte)
  }

  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '')
}

function rewriteUpstreamLocation(location, { incomingUrl, targetUrl, isAppsHost }) {
  try {
    const resolved = new URL(location, targetUrl)
    const rewritten = new URL(incomingUrl.toString())

    rewritten.hostname = incomingUrl.hostname
    rewritten.protocol = incomingUrl.protocol
    rewritten.port = incomingUrl.port

    let nextPath = resolved.pathname
    if (isAppsHost) {
      if (!nextPath.startsWith(APPS_BASE_PATH)) {
        nextPath = `${APPS_BASE_PATH}${nextPath.startsWith('/') ? '' : '/'}${nextPath}`
      }
    } else if (nextPath.startsWith(APPS_BASE_PATH)) {
      nextPath = nextPath.slice(APPS_BASE_PATH.length) || '/'
    }

    rewritten.pathname = nextPath
    rewritten.search = resolved.search
    rewritten.hash = resolved.hash

    return rewritten.toString()
  } catch {
    return location
  }
}

function timingSafeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false
  if (a.length !== b.length) return false

  let result = 0
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i)
  }
  return result === 0
}