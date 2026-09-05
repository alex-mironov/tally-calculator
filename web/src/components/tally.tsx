// tally.tsx — the running tab, drawn the way the "Shared Tab" design draws it:
// one card holding the labelled rows and, on the inverted surface at its foot,
// the total. Numbers are mono; a row's workings sit inline before its amount,
// with reference tokens as named pills rather than raw `{e12}` syntax.
// Shared by the share page and the marketing page so both show the same object.
import { fmt, showExpr, splitExpr } from '@/lib/format';
import type { SharedEntry } from '@/lib/share';

/** An expression with its `{e12}` / `{sum}` tokens drawn as named pills. */
export function ExprLine({ expr, entries }: { expr: string; entries: SharedEntry[] }) {
  return (
    <span className="expr">
      {splitExpr(expr, entries).map((seg, i) =>
        seg.type === 'text' ? (
          <span key={i}>{seg.text}</span>
        ) : (
          <span key={i} className="ref-pill">
            {seg.label}
          </span>
        ),
      )}
    </span>
  );
}

export function TallyRow({
  entry,
  entries,
  className = '',
  style,
}: {
  entry: SharedEntry;
  entries: SharedEntry[];
  /** extra classes on the row itself — the row must stay a direct child of
   *  `.tally` or the separator rule (`.tally-row + .tally-row`) stops matching */
  className?: string;
  style?: React.CSSProperties;
}) {
  const label = entry.note || (entry.num != null ? `Item ${entry.num}` : 'Item');
  // the app's two off-states: not counted (muted, ⊘ by the amount) and in
  // error (a dash for the amount, the workings in red)
  const state = entry.error ? 'error' : entry.excluded ? 'excluded' : '';
  return (
    <div className={`tally-row ${state} ${className}`.replace(/\s+/g, ' ').trim()} style={style}>
      <span className="row-body">
        <span className="note-label">{label}</span>
        {showExpr(entry) && <ExprLine expr={entry.expr} entries={entries} />}
      </span>
      <span className="val">
        {entry.excluded && <ExcludedMark />}
        {entry.error ? '—' : fmt(entry.value)}
      </span>
    </div>
  );
}

/** ⊘ — SF Symbols' circle.slash, redrawn so it matches the app's row. */
function ExcludedMark() {
  return (
    <svg className="excluded-mark" viewBox="0 0 12 12" aria-label="not counted in total" role="img">
      <circle cx="6" cy="6" r="4.75" fill="none" stroke="currentColor" strokeWidth="1.4" />
      <path d="M2.8 9.2 9.2 2.8" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
    </svg>
  );
}

/**
 * The card. `children` are the rows; the total is drawn inside, at the foot,
 * so the tab reads as one object rather than a list with a separate answer.
 */
export function TallyCard({
  children,
  total,
  label = 'Total',
  className = '',
}: {
  children: React.ReactNode;
  total: number;
  label?: string;
  className?: string;
}) {
  return (
    <section className={`tally ${className}`.trim()}>
      {children}
      <div className="tally-total">
        <span className="lab">{label}</span>
        <span className="val">{fmt(total)}</span>
      </div>
    </section>
  );
}
