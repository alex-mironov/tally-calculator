// tally-share — Cloudflare Worker behind Tally Calculator's share links,
// a Hono app served through Vite (see vite.config.ts).
//
//   POST /api/shares      store a snapshot, get { id, url, api } back
//   GET  /api/shares/:id  the raw snapshot (JSON) — the app's import path
//   GET  /s/:id           the human-readable share page (Hono JSX)
//
// Snapshots are immutable and anonymous; a share link is a capability — the
// random id is the only key. Links expire after a year (KV TTL).
import { Hono, type Context } from 'hono';
import { cors } from 'hono/cors';
import { html } from 'hono/html';
import type { HtmlEscapedString } from 'hono/utils/html';

import { MessagePage, SharePage } from './render';
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

const ID_PATH_RE = /^[A-Za-z0-9]{6,32}$/;

// The pages are fully inline — the CSP locks everything else out.
const PAGE_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'",
};

const app = new Hono<{ Bindings: Env }>();

app.use('/api/*', cors({ origin: '*', allowMethods: ['GET', 'POST', 'OPTIONS'] }));

app.onError((e, c) => {
  console.log(JSON.stringify({ level: 'error', path: c.req.path, message: e.message }));
  return c.json({ error: 'internal error' }, 500);
});

// c.html() renders a JSX tree without a doctype — wrap so browsers don't
// fall into quirks mode.
const doc = (node: HtmlEscapedString | Promise<HtmlEscapedString>) => html`<!DOCTYPE html>${node}`;

const notFoundPage = (c: Context<{ Bindings: Env }>) =>
  c.html(doc(<MessagePage title="This share link has expired" sub="…or it never existed. Ask for a fresh link." />), 404, PAGE_HEADERS);

// ── store a snapshot ────────────────────────────────────────────────────────
app.post('/api/shares', async (c) => {
  const len = Number(c.req.header('content-length') || '0');
  if (!len || len > MAX_BODY_BYTES) return c.json({ error: 'body too large or missing content-length' }, 413);

  let raw: unknown;
  try {
    raw = await c.req.json();
  } catch {
    return c.json({ error: 'invalid JSON' }, 400);
  }
  const payload = validatePayload(raw);
  if (typeof payload === 'string') return c.json({ error: payload }, 400);

  const id = newId();
  const stored: StoredShare = { ...payload, createdAt: Date.now() };
  await c.env.SHARES.put(`share:${id}`, JSON.stringify(stored), { expirationTtl: TTL_SECONDS });

  const origin = new URL(c.req.url).origin;
  return c.json({ id, url: `${origin}/s/${id}`, api: `${origin}/api/shares/${id}` }, 201);
});

// ── raw snapshot for the app ────────────────────────────────────────────────
app.get('/api/shares/:id', async (c) => {
  const id = c.req.param('id');
  if (!ID_PATH_RE.test(id)) return c.json({ error: 'not found' }, 404);
  const body = await c.env.SHARES.get(`share:${id}`);
  if (body == null) return c.json({ error: 'not found' }, 404);
  return c.body(body, 200, { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' });
});

// ── the share page ──────────────────────────────────────────────────────────
app.get('/s/:id', async (c) => {
  const id = c.req.param('id');
  if (!ID_PATH_RE.test(id)) return notFoundPage(c);
  const share = await c.env.SHARES.get<StoredShare>(`share:${id}`, 'json');
  if (share == null) return notFoundPage(c);
  return c.html(doc(<SharePage share={share} id={id} />), 200, PAGE_HEADERS);
});

app.get('/', (c) => c.html(doc(<MessagePage title="Tally Calculator" sub="Share links live at /s/<id>." />), 200, PAGE_HEADERS));

app.notFound((c) => c.json({ error: 'not found' }, 404));

export default app;
