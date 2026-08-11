// The marketing page. Prerendered to static HTML at build time (see
// vite.config.ts) — it has no per-request data, so there's no reason for a
// visitor to wait on a render.
//
// The pitch is the hero: a working running tab whose derived lines recompute
// when you change an input. It's the one thing the app does that a keypad
// calculator can't, so it's shown rather than claimed.
import { createFileRoute } from '@tanstack/react-router';

import { LiveTally } from '@/components/live-tally';
import { TallyRow, TotalBar } from '@/components/tally';

/**
 * Set this when the app reaches the App Store; until then the page says so
 * rather than linking somewhere that isn't ready.
 */
const APP_STORE_URL: string | null = null;

const DESCRIPTION =
  'Tally is a running-tab calculator for iPhone. Every line keeps its label, its maths and its place — so you can still read the total back a week later.';

export const Route = createFileRoute('/')({
  head: () => ({
    meta: [
      { title: 'Tally Calculator — keep the whole tab, not just the answer' },
      { name: 'description', content: DESCRIPTION },
      { property: 'og:title', content: 'Tally Calculator' },
      { property: 'og:description', content: DESCRIPTION },
      { property: 'og:type', content: 'website' },
    ],
  }),
  component: Home,
});

const FEATURES = [
  {
    token: '{e12}',
    title: 'Lines that point at lines',
    body: 'Reference an earlier amount and it stays live. Correct the original and everything built on it follows — no re-typing, no stale numbers.',
  },
  {
    token: '{sum}',
    title: 'A subtotal you can build on',
    body: 'Point a line at the running total above it. Tips, splits and shares of the bill stay right as the tab grows.',
  },
  {
    token: '#trip',
    title: 'Saved and tagged',
    body: 'Name a calculation, tag it, and find it later. Everything syncs across your devices through iCloud.',
  },
  {
    // each token is real app syntax; this one is the path a share link lands on
    token: '/s/',
    title: 'Shared as a link',
    body: 'Send a tab to anyone. They get a page they can read in the browser — no app required — and can open their own copy if they have one.',
  },
];

function Home() {
  return (
    <>
      <header className="wrap">
        <nav className="nav">
          <a className="brand" href="/">
            <img src="/icon.png" alt="" width="28" height="28" />
            Tally
          </a>
          {APP_STORE_URL ? (
            <a className="btn" href={APP_STORE_URL}>
              Get the app
            </a>
          ) : (
            <span className="note">Coming to the App&nbsp;Store</span>
          )}
        </nav>
      </header>

      <main>
        <section className="wrap hero">
          <div className="hero-copy">
            <p className="eyebrow">Running-tab calculator</p>
            <h1 className="display">
              Keep the whole tab,
              <br />
              not just the answer.
            </h1>
            <p className="lede">
              A calculator clears itself the moment you look away. Tally keeps every line — with the note you
              gave it and the maths behind it — so the total still explains itself a week later.
            </p>
            <div className="hero-cta">
              {APP_STORE_URL ? (
                <a className="btn btn-solid btn-lg" href={APP_STORE_URL}>
                  Get it for iPhone
                </a>
              ) : (
                <a className="btn btn-solid btn-lg" href="#how">
                  See how it works
                </a>
              )}
              <span className="note">iPhone · iOS 26 · in TestFlight now</span>
            </div>
          </div>

          <div>
            <LiveTally />
          </div>
        </section>
      </main>

      <section className="deep" id="how">
        <div className="wrap band">
          <div className="band-head">
            <p className="eyebrow">What it does</p>
            <h2>Built for the tab that keeps growing.</h2>
          </div>
          <div className="features">
            {FEATURES.map((f) => (
              <article className="feature" key={f.token}>
                <span className="token">{f.token}</span>
                <h3>{f.title}</h3>
                <p>{f.body}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="wrap band">
        <div className="split">
          <div>
            <p className="eyebrow">Sharing</p>
            <h2>Send the whole calculation, not a screenshot.</h2>
            <p className="lede">
              Every shared tab becomes a page like this one: the lines, their notes, the workings, the total.
              It opens in any browser, and in the app it becomes a copy the other person can keep editing.
            </p>
            <ol className="steps">
              <li>Tap Share on any calculation in the app.</li>
              <li>Send the link the way you'd send any other.</li>
              <li>They read it in the browser — or open their own copy in Tally.</li>
            </ol>
          </div>
          <div>
            <ExampleShare />
          </div>
        </div>
      </section>

      <footer className="wrap foot">
        <span>Tally Calculator</span>
        <span>No account, no sign-up — your calculations stay on your devices.</span>
      </footer>
    </>
  );
}

/** A miniature of the share page, built from the same components it uses. */
function ExampleShare() {
  const entries = [
    { id: 'e1', num: 1, note: 'Ferry tickets', expr: '', value: 24 },
    { id: 'e2', num: 2, note: 'Lunch · split 3', expr: '54÷3', value: 18 },
    { id: 'e3', num: 3, note: 'Museum', expr: '', value: 12.5 },
  ];
  const total = entries.reduce((a, e) => a + e.value, 0);
  return (
    <div>
      <p className="eyebrow">Shared calculation</p>
      <h3 style={{ fontSize: '22px', fontWeight: 600, letterSpacing: '-0.02em', margin: '6px 0 14px' }}>
        Saturday in Lisbon
      </h3>
      <div className="tally">
        {entries.map((e) => (
          <TallyRow key={e.id} entry={e} entries={entries} />
        ))}
      </div>
      <TotalBar total={total} />
    </div>
  );
}
