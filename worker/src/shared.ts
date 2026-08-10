// shared.ts — the share snapshot's shape, its validation, and the two pieces
// of the mobile app's calc-engine the web page needs (money formatting and
// reference-token display). Kept dependency-free so index.ts and render.ts
// stay small.

/** One line of a shared calculation — mirrors `Entry` in the mobile app. */
export type SharedEntry = {
  /** `e123`-style id; only meaningful for resolving `{e123}` tokens in exprs */
  id: string;
  /** short label, e.g. "Coffee" — may be '' */
  note: string;
  /** raw keypad expression ("60÷4", may embed `{e123}` / `{sum}`) or '' */
  expr: string;
  value: number;
  /** sticky line number from the app, used as the display fallback name */
  num?: number;
};

/** The POST body — a frozen snapshot of one tab. */
export type SharePayload = {
  v: 1;
  name: string;
  tags: string[];
  entries: SharedEntry[];
  /** when the tab was saved in the app, ms epoch — optional */
  savedAt?: number;
  /** sender's accent hex; themes the share page when it's one we know */
  accent?: string;
};

/** What actually lands in KV. */
export type StoredShare = SharePayload & { createdAt: number };

// ── limits ──────────────────────────────────────────────────────────────────
export const MAX_BODY_BYTES = 100_000;
export const MAX_ENTRIES = 300;
const MAX_NOTE = 200;
const MAX_EXPR = 300;
const MAX_NAME = 80;
const MAX_TAGS = 12;
const MAX_TAG = 22;

const ID_RE = /^e\d+$/;
const HEX_RE = /^#[0-9a-fA-F]{6}$/;

/**
 * Validate an untrusted POST body into a normalized SharePayload.
 * Returns a string error for anything off — the app is the only intended
 * client, so there's no need to be forgiving.
 */
export function validatePayload(raw: unknown): SharePayload | string {
  if (typeof raw !== 'object' || raw === null) return 'body must be a JSON object';
  const b = raw as Record<string, unknown>;
  if (b.v !== 1) return 'unsupported payload version';
  if (!Array.isArray(b.entries) || b.entries.length === 0) return 'entries must be a non-empty array';
  if (b.entries.length > MAX_ENTRIES) return `too many entries (max ${MAX_ENTRIES})`;

  const entries: SharedEntry[] = [];
  for (const e of b.entries as unknown[]) {
    if (typeof e !== 'object' || e === null) return 'entry must be an object';
    const x = e as Record<string, unknown>;
    if (typeof x.id !== 'string' || !ID_RE.test(x.id)) return 'entry id must look like e123';
    if (typeof x.value !== 'number' || !isFinite(x.value)) return 'entry value must be a finite number';
    const note = typeof x.note === 'string' ? x.note.slice(0, MAX_NOTE) : '';
    const expr = typeof x.expr === 'string' ? x.expr.slice(0, MAX_EXPR) : '';
    const num =
      typeof x.num === 'number' && Number.isInteger(x.num) && x.num > 0 && x.num < 1e6 ? x.num : undefined;
    entries.push({ id: x.id, note, expr, value: x.value, num });
  }

  const name = typeof b.name === 'string' ? b.name.trim().slice(0, MAX_NAME) : '';
  const tags = Array.isArray(b.tags)
    ? (b.tags as unknown[])
        .filter((t): t is string => typeof t === 'string' && t.trim().length > 0)
        .map((t) => t.trim().slice(0, MAX_TAG))
        .slice(0, MAX_TAGS)
    : [];
  const savedAt =
    typeof b.savedAt === 'number' && isFinite(b.savedAt) && b.savedAt > 0 ? b.savedAt : undefined;
  const accent = typeof b.accent === 'string' && HEX_RE.test(b.accent) ? b.accent : undefined;

  return { v: 1, name, tags, entries, savedAt, accent };
}

// ── display helpers (ported from mobile/src/lib/calc-engine.ts) ─────────────

/**
 * Money-ish formatting: 2dp, thousands separators, keypad '−' for minus.
 * Hand-rolled to render identically to the app.
 */
export function fmt(n: number | null | undefined): string {
  if (n == null || !isFinite(n)) return '0.00';
  const neg = n < 0;
  const [whole, frac] = Math.abs(n).toFixed(2).split('.');
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return (neg ? '−' : '') + grouped + '.' + frac;
}

const REF_RE = /\{(e\d+|sum)\}/g;

/**
 * An expression as flat display text: `{e123}` becomes the referenced line's
 * note (or "line N"), `{sum}` becomes "subtotal" — matching how the app's
 * native surfaces read expressions aloud.
 */
export function exprText(raw: string, entries: SharedEntry[]): string {
  const byId = new Map(entries.map((e) => [e.id, e]));
  return raw
    .replace(REF_RE, (_, id: string) => {
      if (id === 'sum') return ' subtotal';
      const ref = byId.get(id);
      if (!ref) return ' ?';
      return ' ' + (ref.note || (ref.num != null ? `line ${ref.num}` : 'line'));
    })
    .trim();
}

/** True when the expression is worth showing under the amount. */
export function showExpr(e: SharedEntry): boolean {
  if (!e.expr) return false;
  // fresh non-global regex — REF_RE is /g/ and carries lastIndex between calls
  return /[\d}]\s*[+\-*/×÷−]\s*[\d{]/.test(e.expr) || /\{(e\d+|sum)\}/.test(e.expr);
}
