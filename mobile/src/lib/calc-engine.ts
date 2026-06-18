// calc-engine.ts — tiny expression evaluator for the Tally keypad.
// Supports + − × ÷, decimals, and iOS-style percent. Ported from the
// concept prototype's calc-engine.jsx.

type Op = '+' | '-' | '*' | '/';

/** Evaluate a flat expression string (no parens). Returns a number or null. */
export function evaluate(raw: string | null | undefined): number | null {
  if (raw == null) return null;
  const s = String(raw)
    .trim()
    .replace(/×/g, '*')
    .replace(/÷/g, '/')
    .replace(/−/g, '-');
  if (!s) return null;

  // tokens: numbers (optionally trailing %) and binary operators
  const toks = s.match(/\d*\.?\d+%?|[+\-*/]/g);
  if (!toks) return null;

  const vals: number[] = [];
  const ops: Op[] = [];
  for (const t of toks) {
    if (t === '+' || t === '-' || t === '*' || t === '/') {
      // ignore a leading operator or a doubled operator
      if (vals.length === 0 || ops.length === vals.length) continue;
      ops.push(t);
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
      vals.push(n);
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
 * True when the string contains a binary operator between numbers (so the
 * row is worth showing the expression under the amount).
 */
export function hasOperator(raw: string | null | undefined): boolean {
  if (!raw) return false;
  return /\d\s*[+\-*/×÷−]\s*\d/.test(String(raw));
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
