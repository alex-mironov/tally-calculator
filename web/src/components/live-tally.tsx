// live-tally.tsx — the hero's working running tab.
//
// This is the pitch, demonstrated rather than described: two of the lines are
// *derived* from the others, so changing an input recomputes them and the
// total the way it does on the phone. Tapping an amount is the whole
// interaction — no keypad, no controls to explain.
//
// The full list renders on the server, so the prerendered HTML is complete
// and the staggered entrance is pure CSS on top of it. Nothing shifts.
import { useState } from 'react';

import { TallyRow, TotalBar } from '@/components/tally';
import { fmt } from '@/lib/format';
import type { SharedEntry } from '@/lib/share';

/** The two lines you can change, and by how much a tap moves them. */
const INPUTS = [
  { id: 'e1', num: 1, note: 'Coffee', start: 4.5, step: 0.5, wrap: 9 },
  { id: 'e2', num: 2, note: 'Groceries', start: 42.2, step: 6, wrap: 66 },
] as const;

type Inputs = { e1: number; e2: number };

/**
 * Build the tab from its inputs. Line 4 references line 1 and line 5
 * references the subtotal above it — the same `{e1}` / `{sum}` tokens the app
 * writes, resolved here the same way.
 */
function buildTab(v: Inputs): SharedEntry[] {
  const rows: SharedEntry[] = [
    { id: 'e1', num: 1, note: 'Coffee', expr: '', value: v.e1 },
    { id: 'e2', num: 2, note: 'Groceries', expr: '', value: v.e2 },
    { id: 'e3', num: 3, note: 'Dinner · split 4', expr: '60÷4', value: 15 },
    { id: 'e4', num: 4, note: 'Two more coffees', expr: '{e1}×2', value: v.e1 * 2 },
  ];
  const subtotal = rows.reduce((a, e) => a + e.value, 0);
  rows.push({ id: 'e5', num: 5, note: 'Tip 10%', expr: '{sum}×0.1', value: subtotal * 0.1 });
  return rows;
}

export function LiveTally() {
  const [v, setV] = useState<Inputs>({ e1: INPUTS[0].start, e2: INPUTS[1].start });
  const [bumped, setBumped] = useState<string | null>(null);

  const rows = buildTab(v);
  const total = rows.reduce((a, e) => a + e.value, 0);

  function bump(input: (typeof INPUTS)[number]) {
    setV((cur) => {
      const next = cur[input.id as keyof Inputs] + input.step;
      return { ...cur, [input.id]: next > input.wrap ? input.start : Number(next.toFixed(2)) };
    });
    setBumped(input.id);
    // let the highlight replay on the next tap
    setTimeout(() => setBumped(null), 500);
  }

  return (
    <div>
      <div className="tally">
        {rows.map((e, i) => {
          const input = INPUTS.find((x) => x.id === e.id);
          const style = { animationDelay: `${i * 70}ms` };
          if (!input) {
            return <TallyRow key={e.id} entry={e} entries={rows} className="rise" style={style} />;
          }
          return (
            <button
              key={e.id}
              type="button"
              className={`tally-row tappable rise${bumped === e.id ? ' bumped' : ''}`}
              style={style}
              onClick={() => bump(input)}
              aria-label={`${e.note}, ${fmt(e.value)}. Change this amount`}>
              <span className="note-label">{e.note}</span>
              <span className="val">{fmt(e.value)}</span>
            </button>
          );
        })}
      </div>
      <div className="rise" style={{ animationDelay: `${rows.length * 70}ms` }}>
        <TotalBar total={total} />
      </div>
      <span className="demo-hint">Tap Coffee or Groceries — the linked lines follow</span>
    </div>
  );
}
