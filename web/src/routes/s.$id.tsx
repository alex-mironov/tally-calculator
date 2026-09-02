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

// the design's Apple mark on the "Get the app" pill — Tally is an iPhone app
const AppleMark = () => (
  <svg viewBox="0 0 814 1000" aria-hidden="true">
    <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57-155.5-127C46.7 790.7 0 663 0 541.8c0-194.4 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z" />
  </svg>
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
          <AppleMark />
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
