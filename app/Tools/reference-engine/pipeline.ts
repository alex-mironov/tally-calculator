// pipeline.ts — the live-reference pipeline, lifted verbatim out of
// mobile/src/lib/tally-store.tsx (where the functions are module-private) so the
// fixture generator can run it. Frozen reference: keep it byte-identical to
// what the React Native app shipped, even after mobile/ is deleted, so the
// Swift port's fixture stays reproducible.
//
// The only edits are `export` keywords and this header.
import * as Calc from './calc-engine.ts';

export type Entry = {
  id: string;
  note: string;
  expr: string;
  value: number;
  num?: number;
  excluded?: boolean;
  error?: boolean;
};

/** The total of a list: every counted line. Errored lines carry 0 already. */
export function totalOf(list: Entry[]): number {
  let sum = 0;
  for (const e of list) if (!e.excluded) sum += e.value || 0;
  return sum;
}

export function assignNums(list: Entry[]): Entry[] {
  let next = list.reduce((m, e) => Math.max(m, e.num ?? 0), 0) + 1;
  let changed = false;
  const out = list.map((e) => {
    if (e.num != null) return e;
    changed = true;
    return { ...e, num: next++ };
  });
  return changed ? out : list;
}

/**
 * Replace references to removed lines with their last known value. A removed
 * line that was itself in error has no value worth keeping — its token is left
 * in place, so the dependent goes into error rather than quietly becoming 0.
 */
export function freezeRefs(prev: Entry[], list: Entry[]): Entry[] {
  const kept = new Set(list.map((e) => e.id));
  const removed = new Map(prev.filter((e) => !kept.has(e.id) && !e.error).map((e) => [e.id, e.value]));
  if (removed.size === 0) return list;
  return list.map((e) => {
    if (!e.expr) return e;
    const expr = e.expr.replace(Calc.REF_RE, (tok, id) =>
      removed.has(id) ? Calc.plain(removed.get(id)!) : tok,
    );
    if (expr === e.expr) return e;
    // a pure reference may have frozen into a bare number — no longer worth
    // showing as an expression under the amount
    const keepExpr = Calc.hasOperator(expr) || Calc.refsIn(expr).length > 0;
    return { ...e, expr: keepExpr ? expr : '' };
  });
}

/**
 * Recompute referencing lines top-to-bottom; plain lines keep their value.
 * A line that can't be evaluated is marked `error` and carries 0 — and stays
 * out of `vals`, so anything referencing it errors too rather than reading a
 * number that means nothing. `{sum}` is the counted lines above.
 */
export function recalc(list: Entry[]): Entry[] {
  const vals = new Map<string, number>(); // resolved values; errored lines absent
  let changed = false;
  const out = list.map((e, i) => {
    let v = e.value;
    let err = false;
    if (e.expr && Calc.refsIn(e.expr).length > 0) {
      const r = Calc.evaluate(e.expr, (id) => {
        if (id === 'sum') {
          let sum = 0;
          for (let k = 0; k < i; k++) if (!list[k].excluded) sum += vals.get(list[k].id) ?? 0;
          return sum;
        }
        // only lines above have resolved — a forward reference (impossible
        // through the UI) or an errored line resolves to nothing
        return vals.get(id) ?? null;
      });
      if (r == null) {
        err = true;
        v = 0;
      } else v = r;
    }
    if (!err) vals.set(e.id, v);
    if (v === e.value && !!e.error === err) return e;
    changed = true;
    const next: Entry = { ...e, value: v };
    if (err) next.error = true;
    else delete next.error;
    return next;
  });
  return changed ? out : list;
}

export function pipeline(prev: Entry[], next: Entry[]): Entry[] {
  return recalc(freezeRefs(prev, assignNums(next)));
}
