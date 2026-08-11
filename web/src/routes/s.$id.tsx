// /s/:id — a shared calculation, server-rendered.
//
// The snapshot is read from KV in a server function so the page arrives fully
// formed: a link pasted into a chat has to render as a page, with real title
// and preview metadata, for someone who has never installed the app.
import { createFileRoute, notFound } from '@tanstack/react-router';
import { createServerFn } from '@tanstack/react-start';
import { env } from 'cloudflare:workers';

import { TallyRow, TotalBar } from '@/components/tally';
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
    const name = loaderData.name || 'Shared calculation';
    const n = loaderData.entries.length;
    const description = `${n} item${n === 1 ? '' : 's'} · total ${total} · shared from Tally Calculator`;
    const title = `${name} — ${total}`;
    return {
      meta: [
        { title },
        { name: 'description', content: description },
        { property: 'og:title', content: title },
        { property: 'og:description', content: description },
        { property: 'og:type', content: 'website' },
        { name: 'twitter:card', content: 'summary' },
        // a share link is a capability handed to specific people; it has no
        // business showing up in search results
        { name: 'robots', content: 'noindex' },
      ],
    };
  },
  component: SharedCalculation,
  notFoundComponent: ExpiredShare,
});

function SharedCalculation() {
  const share = Route.useLoaderData();
  const { id } = Route.useParams();
  const total = totalOf(share.entries);
  const when = share.savedAt ?? share.createdAt;
  const dateStr = new Date(when).toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
  const n = share.entries.length;

  return (
    <div className="share-page">
      <main className="share-main">
        <header className="share-head">
          <div className="eyebrow">Shared calculation</div>
          <h1>{share.name || 'Shared calculation'}</h1>
          <div className="share-meta">
            {dateStr} · {n} line{n === 1 ? '' : 's'}
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
        </header>

        <section className="tally">
          {share.entries.map((e) => (
            <TallyRow key={e.id} entry={e} entries={share.entries} showNumber />
          ))}
        </section>
        <TotalBar total={total} />

        <a className="share-cta" href={`tally://share/${id}`}>
          Open in Tally Calculator
        </a>
        <p className="share-foot">
          A read-only snapshot — opening it in the app makes your own copy.
          <br />
          <a href="/">What is Tally?</a>
        </p>
      </main>
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
