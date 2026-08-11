// POST /api/shares — store a snapshot of a tab and return its link.
//
// Shipped iOS builds call this exact path and read `url` off the response;
// treat the contract as frozen. Snapshots are immutable and anonymous — the
// link is a capability, its random id the only key — and expire after a year.
import { createFileRoute } from '@tanstack/react-router';
import { env } from 'cloudflare:workers';

import { MAX_BODY_BYTES, newShareId, validatePayload, type StoredShare } from '@/lib/share';

const TTL_SECONDS = 365 * 24 * 60 * 60;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

const json = (data: unknown, status: number) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });

export const Route = createFileRoute('/api/shares')({
  server: {
    handlers: {
      OPTIONS: () => new Response(null, { status: 204, headers: CORS }),

      POST: async ({ request }) => {
        const len = Number(request.headers.get('content-length') || '0');
        if (!len || len > MAX_BODY_BYTES) {
          return json({ error: 'body too large or missing content-length' }, 413);
        }

        let raw: unknown;
        try {
          raw = await request.json();
        } catch {
          return json({ error: 'invalid JSON' }, 400);
        }

        const payload = validatePayload(raw);
        if (typeof payload === 'string') return json({ error: payload }, 400);

        const id = newShareId();
        const stored: StoredShare = { ...payload, createdAt: Date.now() };
        await env.SHARES.put(`share:${id}`, JSON.stringify(stored), { expirationTtl: TTL_SECONDS });

        const origin = new URL(request.url).origin;
        return json({ id, url: `${origin}/s/${id}`, api: `${origin}/api/shares/${id}` }, 201);
      },
    },
  },
});
