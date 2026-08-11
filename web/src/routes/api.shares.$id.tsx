// GET /api/shares/:id — the raw snapshot, for the app's import flow
// (tally://share/<id> → the app files it as a new saved tab).
import { createFileRoute } from '@tanstack/react-router';
import { env } from 'cloudflare:workers';

import { SHARE_ID_RE } from '@/lib/share';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

export const Route = createFileRoute('/api/shares/$id')({
  server: {
    handlers: {
      OPTIONS: () => new Response(null, { status: 204, headers: CORS }),

      GET: async ({ params }) => {
        const notFound = () =>
          new Response(JSON.stringify({ error: 'not found' }), {
            status: 404,
            headers: { 'Content-Type': 'application/json', ...CORS },
          });

        if (!SHARE_ID_RE.test(params.id)) return notFound();
        const body = await env.SHARES.get(`share:${params.id}`);
        if (body == null) return notFound();

        return new Response(body, {
          headers: {
            'Content-Type': 'application/json',
            // snapshots are immutable, so this is safe to hold on to
            'Cache-Control': 'public, max-age=3600',
            ...CORS,
          },
        });
      },
    },
  },
});
