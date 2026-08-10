// tally-share — Cloudflare Worker behind Tally Calculator's share links.
//
//   POST /api/shares      store a snapshot, get { id, url, pageUrl } back
//   GET  /api/shares/:id  the raw snapshot (JSON) — the app's import path
//   GET  /s/:id           the human-readable share page
//
// Snapshots are immutable and anonymous; a share link is a capability — the
// random id is the only key. Links expire after a year (KV TTL).
import { renderShare } from './render';
import { MAX_BODY_BYTES, validatePayload, type StoredShare } from './shared';

const TTL_SECONDS = 365 * 24 * 60 * 60;
const ID_LEN = 11; // base62 → ~65 bits, unguessable and short enough for chat
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

function newId(): string {
  // rejection sampling keeps the distribution uniform (256 % 62 ≠ 0)
  const out: string[] = [];
  const buf = new Uint8Array(32);
  while (out.length < ID_LEN) {
    crypto.getRandomValues(buf);
    for (const b of buf) {
      if (b >= 248) continue; // 248 = 62 * 4
      out.push(ALPHABET[b % 62]);
      if (out.length === ID_LEN) break;
    }
  }
  return out.join('');
}

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });
}

function err(message: string, status: number): Response {
  return json({ error: message }, status);
}

const ID_PATH_RE = /^[A-Za-z0-9]{6,32}$/;

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    const { pathname } = url;

    try {
      if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

      // ── store a snapshot ──────────────────────────────────────────────
      if (request.method === 'POST' && pathname === '/api/shares') {
        const len = Number(request.headers.get('content-length') || '0');
        if (!len || len > MAX_BODY_BYTES) return err('body too large or missing content-length', 413);

        let raw: unknown;
        try {
          raw = await request.json();
        } catch {
          return err('invalid JSON', 400);
        }
        const payload = validatePayload(raw);
        if (typeof payload === 'string') return err(payload, 400);

        const id = newId();
        const stored: StoredShare = { ...payload, createdAt: Date.now() };
        await env.SHARES.put(`share:${id}`, JSON.stringify(stored), { expirationTtl: TTL_SECONDS });

        return json({ id, url: `${url.origin}/s/${id}`, api: `${url.origin}/api/shares/${id}` }, 201);
      }

      // ── raw snapshot for the app ──────────────────────────────────────
      if (request.method === 'GET' && pathname.startsWith('/api/shares/')) {
        const id = pathname.slice('/api/shares/'.length);
        if (!ID_PATH_RE.test(id)) return err('not found', 404);
        const body = await env.SHARES.get(`share:${id}`);
        if (body == null) return err('not found', 404);
        return new Response(body, {
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'public, max-age=3600',
            ...CORS,
          },
        });
      }

      // ── the share page ────────────────────────────────────────────────
      if (request.method === 'GET' && pathname.startsWith('/s/')) {
        const id = pathname.slice('/s/'.length);
        if (!ID_PATH_RE.test(id)) return notFoundPage();
        const share = await env.SHARES.get<StoredShare>(`share:${id}`, 'json');
        if (share == null) return notFoundPage();
        return htmlResponse(renderShare(share, id));
      }

      if (request.method === 'GET' && pathname === '/') {
        return htmlResponse(landingPage());
      }

      return err('not found', 404);
    } catch (e) {
      console.log(JSON.stringify({ level: 'error', path: pathname, message: e instanceof Error ? e.message : String(e) }));
      return err('internal error', 500);
    }
  },
} satisfies ExportedHandler<Env>;

function htmlResponse(html: string, status = 200): Response {
  return new Response(html, {
    status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'no-referrer',
      // the page is fully inline — lock everything else out
      'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'",
    },
  });
}

function notFoundPage(): Response {
  return htmlResponse(
    `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Not found — Tally Calculator</title><style>body{font:15px/1.5 ui-sans-serif,-apple-system,sans-serif;background:#ececef;color:#1a1a1d;display:flex;min-height:100vh;align-items:center;justify-content:center;text-align:center;padding:24px}@media(prefers-color-scheme:dark){body{background:#161618;color:#f3f3f5}}p{color:#8a8a92;margin-top:8px}</style></head><body><main><h1>This share link has expired</h1><p>…or it never existed. Ask for a fresh link.</p></main></body></html>`,
    404,
  );
}

function landingPage(): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Tally Calculator</title><style>body{font:15px/1.5 ui-sans-serif,-apple-system,sans-serif;background:#ececef;color:#1a1a1d;display:flex;min-height:100vh;align-items:center;justify-content:center;text-align:center;padding:24px}@media(prefers-color-scheme:dark){body{background:#161618;color:#f3f3f5}}p{color:#8a8a92;margin-top:8px}</style></head><body><main><h1>Tally Calculator</h1><p>Share links live at /s/&lt;id&gt;.</p></main></body></html>`;
}
