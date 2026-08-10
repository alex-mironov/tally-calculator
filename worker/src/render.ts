// render.ts — the share page. One self-contained HTML document per snapshot:
// no external assets, both themes via prefers-color-scheme, palette copied
// from the app's Design System v2 tokens (mobile/src/constants/tokens.ts) so
// a shared tab looks like the tab it came from.
import { exprText, fmt, showExpr, type StoredShare } from './shared';

// The app's accent tokens (name → readable ink shades + soft surfaces).
// `accent` in the payload is the raw hue; we theme with the ink/soft pair.
const ACCENTS: Record<string, { softLight: string; softDark: string; inkLight: string; inkDark: string }> = {
  '#0a7aff': { softLight: '#d0e4fb', softDark: '#0c2645', inkLight: '#005fd1', inkDark: '#338efa' }, // Blue
  '#dd1b80': { softLight: '#f6d5e6', softDark: '#3f122a', inkLight: '#b81268', inkDark: '#e654a0' }, // Magenta
  '#00c2a0': { softLight: '#d0fbf4', softDark: '#0c453b', inkLight: '#007b65', inkDark: '#05bd9d' }, // Teal
  '#6b00d0': { softLight: '#e6d0fb', softDark: '#2a0c45', inkLight: '#6b00d0', inkDark: '#ad5afb' }, // Purple
  '#e6b800': { softLight: '#fbf3d0', softDark: '#453a0c', inkLight: '#856a00', inkDark: '#e0b506' }, // Amber
  '#4a5560': { softLight: '#e3e6e8', softDark: '#25292c', inkLight: '#495561', inkDark: '#8592a0' }, // Graphite
};
const DEFAULT_ACCENT = ACCENTS['#0a7aff'];

function esc(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export function renderShare(share: StoredShare, id: string): string {
  const ac = (share.accent && ACCENTS[share.accent.toLowerCase()]) || DEFAULT_ACCENT;
  const total = share.entries.reduce((a, e) => a + (e.value || 0), 0);
  const title = share.name || 'Shared calculation';
  const count = share.entries.length;
  const desc = `${count} item${count === 1 ? '' : 's'} · total ${fmt(total)} · shared from Tally Calculator`;
  const when = share.savedAt ?? share.createdAt;
  const dateStr = new Date(when).toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });

  const rows = share.entries
    .map((e) => {
      const label = e.note || (e.num != null ? `Item ${e.num}` : 'Item');
      const sub = showExpr(e) ? `<div class="expr">${esc(exprText(e.expr, share.entries))}</div>` : '';
      return `<li class="row"><div class="lhs"><div class="note">${esc(label)}</div>${sub}</div><div class="val">${fmt(e.value)}</div></li>`;
    })
    .join('\n');

  const tags = share.tags.length
    ? `<div class="tags">${share.tags.map((t) => `<span class="tag">${esc(t)}</span>`).join('')}</div>`
    : '';

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex">
<title>${esc(title)} — ${fmt(total)}</title>
<meta property="og:title" content="${esc(title)} — ${fmt(total)}">
<meta property="og:description" content="${esc(desc)}">
<meta name="description" content="${esc(desc)}">
<style>
  :root {
    --screen: #ececef; --ink: #1a1a1d; --ink2: #6b6b73; --ink3: #a6a6af;
    --line: #e4e4ea; --card: #ffffff; --deep: #1b1b1e; --deep-ink: #f4f4f6;
    --accent-ink: ${ac.inkLight}; --accent-soft: ${ac.softLight};
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --screen: #161618; --ink: #f3f3f5; --ink2: #a4a4ac; --ink3: #65656e;
      --line: #2a2a2e; --card: #1f1f22; --deep: #f3f3f5; --deep-ink: #161618;
      --accent-ink: ${ac.inkDark}; --accent-soft: ${ac.softDark};
    }
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: var(--screen); color: var(--ink);
    font: 15px/1.45 ui-sans-serif, -apple-system, "Segoe UI", Roboto, sans-serif;
    -webkit-font-smoothing: antialiased;
    padding: 24px 16px calc(24px + env(safe-area-inset-bottom));
    display: flex; justify-content: center;
  }
  main { width: 100%; max-width: 440px; }
  .head { padding: 4px 4px 16px; }
  .kicker { font-size: 12px; font-weight: 600; letter-spacing: 0.04em; text-transform: uppercase; color: var(--accent-ink); }
  h1 { font-size: 24px; font-weight: 600; letter-spacing: -0.01em; margin-top: 4px; }
  .date { font-size: 13px; color: var(--ink3); margin-top: 2px; }
  .tags { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px; }
  .tag { font-size: 12px; font-weight: 600; color: var(--accent-ink); background: var(--accent-soft); border-radius: 999px; padding: 3px 10px; }
  .card { background: var(--card); border-radius: 16px; overflow: hidden; }
  ul { list-style: none; }
  .row { display: flex; align-items: baseline; justify-content: space-between; gap: 16px; padding: 12px 16px; }
  .row + .row { border-top: 1px solid var(--line); }
  .note { font-weight: 500; overflow-wrap: anywhere; }
  .expr { font-size: 12px; color: var(--ink2); margin-top: 1px; font-family: ui-monospace, "SF Mono", Menlo, monospace; }
  .val { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-variant-numeric: tabular-nums; white-space: nowrap; }
  .total { display: flex; align-items: baseline; justify-content: space-between; gap: 16px; background: var(--deep); color: var(--deep-ink); border-radius: 16px; padding: 14px 16px; margin-top: 12px; }
  .total .lab { font-size: 13px; font-weight: 600; opacity: 0.72; }
  .total .val { font-size: 19px; font-weight: 600; }
  .open { display: block; text-align: center; margin-top: 20px; padding: 12px 16px; border-radius: 999px; background: var(--accent-soft); color: var(--accent-ink); font-weight: 600; text-decoration: none; }
  .foot { text-align: center; font-size: 12px; color: var(--ink3); margin-top: 16px; }
</style>
</head>
<body>
<main>
  <header class="head">
    <div class="kicker">Shared calculation</div>
    <h1>${esc(title)}</h1>
    <div class="date">${esc(dateStr)}</div>
    ${tags}
  </header>
  <section class="card"><ul>
${rows}
  </ul></section>
  <div class="total"><span class="lab">Total</span><span class="val">${fmt(total)}</span></div>
  <a class="open" href="tally://share/${esc(id)}">Open in Tally Calculator</a>
  <p class="foot">A read-only snapshot — opening it in the app makes your own copy.</p>
</main>
</body>
</html>`;
}
