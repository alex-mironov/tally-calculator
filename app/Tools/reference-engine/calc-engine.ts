// calc-engine.ts — tiny expression evaluator for the Tally keypad.
// Supports + − × ÷, decimals, iOS-style percent, and reference tokens.
// Ported from the concept prototype's calc-engine.jsx.
//
// References: an expression may embed `{e123}` (the value of another line in
// the same tab, by entry id) or `{sum}` (the running total of every line above
// this one). Tokens are resolved through a caller-supplied resolver at
// evaluation time, so lines stay *live* — edit the referenced line and every
// dependent recomputes (see the recalc pass in tally-store).

type Op = '+' | '-' | '*' | '/';

/** Resolves a reference token to a number. `id` is `e123`-style or `sum`. */
export type RefResolver = (id: string) => number | null;

/** One reference token, e.g. `{e103}` or `{sum}`. */
export const REF_RE = /\{(e\d+|sum)\}/g;

/** All reference ids used by an expression, in order of appearance. */
export function refsIn(raw: string | null | undefined): string[] {
  if (!raw) return [];
  return Array.from(String(raw).matchAll(REF_RE), (m) => m[1]);
}

/** An expression split into literal text runs and reference tokens. */
export type ExprSeg = { type: 'text'; text: string } | { type: 'ref'; id: string };

/** Split an expression for display — text runs stay text, tokens become refs. */
export function splitExpr(raw: string): ExprSeg[] {
  const out: ExprSeg[] = [];
  let last = 0;
  for (const m of String(raw).matchAll(REF_RE)) {
    if (m.index > last) out.push({ type: 'text', text: raw.slice(last, m.index) });
    out.push({ type: 'ref', id: m[1] });
    last = m.index + m[0].length;
  }
  if (last < raw.length) out.push({ type: 'text', text: raw.slice(last) });
  return out;
}

/**
 * An expression as one flat display string, with each reference token replaced
 * by its name — "65×{e12}" reads as "65× Rate". For the places that can't draw
 * pills, like the native selection sheet's row detail.
 */
export function exprText(raw: string, nameFor: (id: string) => string): string {
  return splitExpr(raw)
    .map((s) => (s.type === 'text' ? s.text : ` ${nameFor(s.id)}`))
    .join('')
    .trim();
}

/**
 * Evaluate a flat expression string (no parens). Returns a number or null.
 * Reference tokens are resolved through `resolve`; an unresolvable token
 * makes the whole expression invalid (null) rather than silently wrong.
 */
export function evaluate(raw: string | null | undefined, resolve?: RefResolver): number | null {
  if (raw == null) return null;
  const s = String(raw)
    .trim()
    .replace(/×/g, '*')
    .replace(/÷/g, '/')
    .replace(/−/g, '-');
  if (!s) return null;

  // tokens: references, numbers (optionally trailing %) and binary operators
  const toks = s.match(/\{(?:e\d+|sum)\}|\d*\.?\d+%?|[+\-*/]/g);
  if (!toks) return null;

  const vals: number[] = [];
  const ops: Op[] = [];
  // set when a '-' appears where a value is expected (start of the expression
  // or right after an operator) — a unary minus, applied to the next value
  let neg = false;
  for (const t of toks) {
    if (t === '+' || t === '-' || t === '*' || t === '/') {
      if (vals.length === 0 || ops.length === vals.length) {
        // where a value belongs: '-' negates the value to come, anything else
        // is a stray operator and is dropped
        if (t === '-') neg = !neg;
        continue;
      }
      ops.push(t);
    } else if (t.startsWith('{')) {
      const v = resolve?.(t.slice(1, -1));
      if (v == null || !isFinite(v)) return null;
      vals.push(neg ? -v : v);
      neg = false;
    } else {
      const pct = t.endsWith('%');
      let n = parseFloat(pct ? t.slice(0, -1) : t);
      if (!isFinite(n)) continue;
      if (pct) {
        const lastOp = ops[ops.length - 1];
        const prev = vals[vals.length - 1];
        if (prev !== undefined && (lastOp === '+' || lastOp === '-')) n = (prev * n) / 100;
        else n = n / 100;
      }
      vals.push(neg ? -n : n);
      neg = false;
    }
  }
  if (vals.length === 0) return null;

  // drop a trailing operator (incomplete expression)
  while (ops.length >= vals.length) ops.pop();

  // first pass: * and /
  const rv: number[] = [vals[0]];
  const ro: Op[] = [];
  for (let k = 0; k < ops.length; k++) {
    const op = ops[k];
    const next = vals[k + 1];
    if (op === '*') rv[rv.length - 1] *= next;
    else if (op === '/') rv[rv.length - 1] = next === 0 ? NaN : rv[rv.length - 1] / next;
    else {
      ro.push(op);
      rv.push(next);
    }
  }
  let res = rv[0];
  for (let k = 0; k < ro.length; k++) res = ro[k] === '+' ? res + rv[k + 1] : res - rv[k + 1];
  if (!isFinite(res)) return null;
  return res;
}

/**
 * True when the string contains a binary operator between values (so the
 * row is worth showing the expression under the amount). `}` and `{` count
 * as value edges so `{e1}×3` reads as an operation too.
 */
export function hasOperator(raw: string | null | undefined): boolean {
  if (!raw) return false;
  return /[\d}]\s*[+\-*/×÷−]\s*[\d{]/.test(String(raw));
}

/**
 * A number as plain expression text: round-tripped through 2dp so float
 * artifacts don't leak into expressions, minus rendered with the keypad's
 * '−'. Used when a deleted line's references freeze into literals.
 */
export function plain(n: number): string {
  const r = Math.round(n * 100) / 100;
  return r < 0 ? '−' + String(-r) : String(r);
}

/**
 * Format a number as money-ish: 2dp, thousands separators, trimmed.
 * Written by hand to stay deterministic across platforms (Hermes Intl varies).
 */
export function fmt(n: number | null | undefined): string {
  if (n == null || !isFinite(n)) return '0.00';
  const neg = n < 0;
  const [whole, frac] = Math.abs(n).toFixed(2).split('.');
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return (neg ? '−' : '') + grouped + '.' + frac;
}
