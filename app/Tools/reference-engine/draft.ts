// draft.ts — the keypad's effect on the draft string, lifted out of
// mobile/src/app/index.tsx (`press`, `insertRef`) and
// mobile/src/components/tally/expr-view.tsx (`draftLength`, `draftFontSize`).
//
// Frozen reference: keep byte-identical to what the React Native app shipped,
// even after mobile/ is deleted, so the Swift port's fixture stays reproducible.
//
// The only edits are `export` keywords, this header, and splitting `press` into
// the pure string transformation below plus the three keys that are commands
// rather than edits (AC clears, ✎ toggles the note field, ↵ commits) — those
// touch state the calculator screen owns, not the draft.
import * as Calc from './calc-engine.ts';

export type Key =
  | '⌫' | 'AC' | '%' | '÷'
  | '7' | '8' | '9' | '×'
  | '4' | '5' | '6' | '−'
  | '1' | '2' | '3' | '+'
  | '✎' | '0' | '.' | '↵';

/** The keys that are commands, not edits to the draft string. */
export const COMMANDS: Key[] = ['AC', '✎', '↵'];

/**
 * A key's effect on the draft. Returns the new draft, or null for a key the
 * screen handles itself.
 */
export function applyKey(d: string, k: Key): string | null {
  if (k === 'AC' || k === '✎' || k === '↵') return null;
  // backspace removes a whole reference pill, never half a token
  if (k === '⌫') return d.replace(/\{(?:e\d+|sum)\}$|.$/, '');
  if (k === '%') return /\d$/.test(d) ? d + '%' : d;
  if ('+−×÷'.indexOf(k) >= 0) {
    if (d === '') return k === '−' ? '−' : '';
    if (/[+\-−×÷*/]$/.test(d)) return d.slice(0, -1) + k;
    return d + k;
  }
  if (k === '.') {
    const seg = d.split(/[+\-−×÷*/]/).pop() ?? '';
    if (seg.endsWith('}')) return d; // a pill is a finished number
    if (seg.indexOf('.') >= 0) return d;
    return d === '' ? '0.' : d + '.';
  }
  // a digit straight after a pill starts a new term — join with + (the
  // running-tab default), same rule the Σ insert uses in the other direction
  return /\}$/.test(d) ? d + '+' + k : d + k;
}

/**
 * Drop a reference token into the draft. Mid-number (or right after another
 * pill) a running tab adds things, so joining with + is the predictable
 * default — and the preview shows exactly what happened.
 */
export function insertRef(d: string, id: string): string {
  const tok = `{${id}}`;
  if (d === '') return tok;
  if (/[+−×÷*/]$/.test(d)) return d + tok;
  return d + '+' + tok;
}

/**
 * Rendered width of a draft, in characters. Reference tokens count as the name
 * actually drawn in the pill, not as their `{e123}` source — otherwise a draft
 * holding one short pill would be treated as long and shrink for no reason.
 */
export function draftLength(expr: string, nameFor: (id: string) => string): number {
  return Calc.splitExpr(expr).reduce(
    (n, s) => n + (s.type === 'text' ? s.text.length : nameFor(s.id).length + 1),
    0,
  );
}

export const DRAFT_FONT_SIZE = 36;

/**
 * One step down once the line is long enough to crowd the card, mirroring the
 * design's 40 → 30. Past that the line stops shrinking and starts running off
 * the leading edge: shrinking all the way to fit would make a long sum
 * unreadable, and the head of it matters far less than the digits still being
 * typed.
 */
export const draftFontSize = (len: number): number => (len > 11 ? 27 : DRAFT_FONT_SIZE);
