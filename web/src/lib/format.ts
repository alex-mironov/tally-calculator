// format.ts — the display half of the app's calc engine, ported from
// mobile/src/lib/calc-engine.ts so a shared tab reads on the web exactly as it
// does on the phone. Isomorphic: the share page renders with it on the server,
// the hero tally uses it in the browser.
import type { SharedEntry } from './share';

/**
 * Money-ish formatting: 2dp, thousands separators, the keypad's '−' for minus.
 * Hand-rolled rather than Intl so it matches the app byte for byte.
 */
export function fmt(n: number | null | undefined): string {
  if (n == null || !isFinite(n)) return '0.00';
  const neg = n < 0;
  const [whole, frac] = Math.abs(n).toFixed(2).split('.');
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return (neg ? '−' : '') + grouped + '.' + frac;
}

const REF_RE = /\{(e\d+|sum)\}/g;

/** An expression split into literal runs and reference tokens, for pill rendering. */
export type ExprSeg = { type: 'text'; text: string } | { type: 'ref'; id: string; label: string };

/** The display name of a referenced line — its note, else its sticky number. */
export function refLabel(id: string, entries: SharedEntry[]): string {
  if (id === 'sum') return 'subtotal';
  const ref = entries.find((e) => e.id === id);
  if (!ref) return '?';
  return ref.note || (ref.num != null ? `line ${ref.num}` : 'line');
}

/**
 * Split an expression for display — text runs stay text, `{e123}`/`{sum}`
 * tokens become refs carrying the label to draw in the pill.
 */
export function splitExpr(raw: string, entries: SharedEntry[]): ExprSeg[] {
  const out: ExprSeg[] = [];
  let last = 0;
  for (const m of raw.matchAll(REF_RE)) {
    if (m.index > last) out.push({ type: 'text', text: raw.slice(last, m.index) });
    out.push({ type: 'ref', id: m[1], label: refLabel(m[1], entries) });
    last = m.index + m[0].length;
  }
  if (last < raw.length) out.push({ type: 'text', text: raw.slice(last) });
  return out;
}

/** The same expression as one flat string — for meta descriptions and alt text. */
export function exprText(raw: string, entries: SharedEntry[]): string {
  return splitExpr(raw, entries)
    .map((s) => (s.type === 'text' ? s.text : ` ${s.label}`))
    .join('')
    .trim();
}

/** True when the expression is worth showing under the amount. */
export function showExpr(e: SharedEntry): boolean {
  if (!e.expr) return false;
  return /[\d}]\s*[+\-*/×÷−]\s*[\d{]/.test(e.expr) || /\{(e\d+|sum)\}/.test(e.expr);
}

export const totalOf = (entries: SharedEntry[]) => entries.reduce((a, e) => a + (e.value || 0), 0);
