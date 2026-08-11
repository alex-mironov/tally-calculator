// tally.tsx — the running tab, drawn the way the app draws it: a card of
// labelled rows over an inverted total bar, numbers in mono, and reference
// tokens as pills rather than raw `{e12}` syntax. Shared by the share page
// and the marketing hero so both show the same object.
import { fmt, showExpr, splitExpr } from '@/lib/format';
import type { SharedEntry } from '@/lib/share';

/** An expression with its `{e12}` / `{sum}` tokens drawn as named pills. */
export function ExprLine({ expr, entries }: { expr: string; entries: SharedEntry[] }) {
  return (
    <div className="expr">
      {splitExpr(expr, entries).map((seg, i) =>
        seg.type === 'text' ? (
          <span key={i}>{seg.text}</span>
        ) : (
          <span key={i} className="ref-pill">
            {seg.label}
          </span>
        ),
      )}
    </div>
  );
}

export function TallyRow({
  entry,
  entries,
  showNumber = false,
  className = '',
  style,
}: {
  entry: SharedEntry;
  entries: SharedEntry[];
  showNumber?: boolean;
  /** extra classes on the row itself — the row must stay a direct child of
   *  `.tally` or the separator rule (`.tally-row + .tally-row`) stops matching */
  className?: string;
  style?: React.CSSProperties;
}) {
  const label = entry.note || (entry.num != null ? `Item ${entry.num}` : 'Item');
  return (
    <div className={`tally-row ${className}`.trim()} style={style}>
      <div>
        <div className="note-label">
          {showNumber && entry.num != null && <span className="line-no">{entry.num}</span>}
          {label}
        </div>
        {showExpr(entry) && <ExprLine expr={entry.expr} entries={entries} />}
      </div>
      <div className="val">{fmt(entry.value)}</div>
    </div>
  );
}

export function TotalBar({ total, label = 'Total' }: { total: number; label?: string }) {
  return (
    <div className="total-bar">
      <span className="lab">{label}</span>
      <span className="val">{fmt(total)}</span>
    </div>
  );
}
