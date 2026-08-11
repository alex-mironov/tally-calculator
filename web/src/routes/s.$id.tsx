// /s/:id — a shared calculation, server-rendered, laid out per the
// "Shared Tab" design in the Calculator design project.
//
// The snapshot is read from KV in a server function so the page arrives fully
// formed: a link pasted into a chat has to render as a page, with real title
// and preview metadata, for someone who has never installed the app.
import { createFileRoute, notFound } from '@tanstack/react-router';
import { createServerFn } from '@tanstack/react-start';
import { env } from 'cloudflare:workers';

import { ShareActions } from '@/components/share-actions';
import { TallyCard, TallyRow } from '@/components/tally';
import { fmt, totalOf } from '@/lib/format';
import { SHARE_ID_RE, type StoredShare } from '@/lib/share';

const getShare = createServerFn({ method: 'GET' })
  .inputValidator((id: string) => id)
  .handler(async ({ data: id }): Promise<StoredShare | null> => {
    if (!SHARE_ID_RE.test(id)) return null;
    return await env.SHARES.get<StoredShare>(`share:${id}`, 'json');
  });

export const Route = createFileRoute('/s/$id')({
  loader: async ({ params }) => {
    const share = await getShare({ data: params.id });
    if (!share) throw notFound();
    return share;
  },
  head: ({ loaderData }) => {
    if (!loaderData) return {};
    const total = fmt(totalOf(loaderData.entries));
    const name = loaderData.name || 'Shared tab';
    const n = loaderData.entries.length;
    const description = `${n} item${n === 1 ? '' : 's'} · total ${total} · shared from Tally Calculator`;
    const title = `${name} — Tally`;
    return {
      meta: [
        { title },
        { name: 'description', content: description },
        { property: 'og:title', content: `${name} — ${total}` },
        { property: 'og:description', content: description },
        { property: 'og:type', content: 'website' },
        { name: 'twitter:card', content: 'summary' },
        // a share link is a capability handed to specific people; it has no
        // business showing up in search results
        { name: 'robots', content: 'noindex' },
      ],
    };
  },
  component: SharedTab,
  notFoundComponent: ExpiredShare,
});

const BrandMark = () => (
  <span className="logo">
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden="true">
      <path d="M3 4.5h10M3 8h10M3 11.5h6" />
    </svg>
  </span>
);

function SharedTab() {
  const share = Route.useLoaderData();
  const { id } = Route.useParams();
  const total = totalOf(share.entries);
  const n = share.entries.length;
  const when = share.savedAt ?? share.createdAt;
  const dateStr = new Date(when).toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });

  return (
    <div className="share-page">
      <header className="share-brand">
        <a className="brand" href="/">
          <BrandMark />
          Tally
        </a>
        <a className="get" href="/">
          Get the app
        </a>
      </header>

      <div className="share-head">
        <p className="share-meta">
          Shared tab · {n} item{n === 1 ? '' : 's'}
        </p>
        <h1>{share.name || 'Shared tab'}</h1>
        {/* the design's line here promised live updates; these snapshots are
            frozen at the moment they were shared, so it says what's true */}
        <p className="share-sub">Shared with you — the tab as it stood on {dateStr}.</p>
      </div>

      {share.tags.length > 0 && (
        <div className="tags">
          {share.tags.map((t) => (
            <span className="tag" key={t}>
              {t}
            </span>
          ))}
        </div>
      )}

      <TallyCard total={total} className="share-card">
        {share.entries.map((e) => (
          <TallyRow key={e.id} entry={e} entries={share.entries} />
        ))}
      </TallyCard>

      <ShareActions id={id} />

      <p className="share-foot">
        This tab is view-only — opening it in the app makes your own copy.
        <br />
        Made with <a href="/">Tally</a> — the running-tab calculator.
      </p>
    </div>
  );
}

function ExpiredShare() {
  return (
    <div className="msg">
      <main>
        <h2>This share link has expired</h2>
        <p>…or it never existed. Ask whoever sent it for a fresh link.</p>
        <a className="btn" href="/">
          What is Tally?
        </a>
      </main>
    </div>
  );
}
