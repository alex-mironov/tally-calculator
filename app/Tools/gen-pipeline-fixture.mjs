// gen-pipeline-fixture.mjs — golden fixture for the live-reference pipeline
// (TallyKit/Tests/TallyKitTests/Fixtures/pipeline.json).
//
// Every write to the live list goes through `pipeline(prev, next)`, which holds
// three invariants no screen is allowed to break:
//
//   1. every line has a sticky number, backfilled for pre-reference data;
//   2. references to lines that just vanished freeze into their last value —
//      unless the vanished line was itself in error, in which case the token
//      stays and the dependent errors rather than quietly becoming 0;
//   3. referencing lines recompute in one forward pass, so list order is
//      evaluation order and cycles cannot exist by construction.
//
// Like the engine fixture, the expected output is produced by running the
// original TypeScript (reference-engine/pipeline.ts), not written by hand.
//
//   node app/Tools/gen-pipeline-fixture.mjs
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { pipeline } from './reference-engine/pipeline.ts';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, '..', 'TallyKit', 'Tests', 'TallyKitTests', 'Fixtures', 'pipeline.json');

/** Shorthand for a line. */
const E = (id, value, extra = {}) => ({ id, note: '', expr: '', value, ...extra });

// ---------------------------------------------------------------------------
// Named scenarios. Each is a (prev, next) pair — what the list was, and what a
// screen just asked it to become.
const SCENARIOS = [
  {
    name: 'seed: fresh list gets sticky numbers from 1',
    prev: [],
    next: [E('e1', 4.5), E('e2', 42.2), E('e3', 18)],
  },
  {
    name: 'a new line takes the next number, never a reused one',
    prev: [E('e1', 1, { num: 1 }), E('e2', 2, { num: 2 })],
    next: [E('e1', 1, { num: 1 }), E('e3', 3)],
  },
  {
    name: 'backfill: legacy entries with no num, in order',
    prev: [],
    next: [E('e1', 1), E('e2', 2, { num: 7 }), E('e3', 3)],
  },
  {
    name: 'a reference recomputes from the line above',
    prev: [],
    next: [E('e1', 10, { num: 1 }), E('e2', 0, { num: 2, expr: '{e1}×3' })],
  },
  {
    name: 'a chain recomputes top to bottom in one pass',
    prev: [],
    next: [
      E('e1', 10, { num: 1 }),
      E('e2', 0, { num: 2, expr: '{e1}×2' }),
      E('e3', 0, { num: 3, expr: '{e2}+{e1}' }),
    ],
  },
  {
    name: '{sum} is the counted lines above it',
    prev: [],
    next: [
      E('e1', 10, { num: 1 }),
      E('e2', 5, { num: 2 }),
      E('e3', 0, { num: 3, expr: '{sum}÷2' }),
      E('e4', 1, { num: 4 }),
    ],
  },
  {
    name: '{sum} skips an excluded line, and the line stays referenceable',
    prev: [],
    next: [
      E('e1', 10, { num: 1 }),
      E('e2', 4, { num: 2, excluded: true }),
      E('e3', 0, { num: 3, expr: '{sum}÷{e2}' }),
    ],
  },
  {
    name: 'deleting a referenced line freezes its value into the expression',
    prev: [E('e1', 10, { num: 1 }), E('e2', 30, { num: 2, expr: '{e1}×3' })],
    next: [E('e2', 30, { num: 2, expr: '{e1}×3' })],
  },
  {
    name: 'a pure reference frozen to a bare number drops its expression',
    prev: [E('e1', 10, { num: 1 }), E('e2', 10, { num: 2, expr: '{e1}' })],
    next: [E('e2', 10, { num: 2, expr: '{e1}' })],
  },
  {
    name: 'deleting an errored line leaves the token, so the dependent errors',
    prev: [
      E('e1', 0, { num: 1, expr: '{gone}', error: true }),
      E('e2', 0, { num: 2, expr: '{e1}+1' }),
    ],
    next: [E('e2', 0, { num: 2, expr: '{e1}+1' })],
  },
  {
    name: 'an unresolvable reference errors and carries 0',
    prev: [],
    next: [E('e1', 99, { num: 1, expr: '{nope}+1' })],
  },
  {
    name: 'error clears again once the reference resolves',
    prev: [E('e1', 0, { num: 1, expr: '{e9}+1', error: true })],
    next: [E('e9', 4, { num: 9 }), E('e1', 0, { num: 1, expr: '{e9}+1', error: true })],
  },
  {
    name: 'an errored line poisons everything below that reads it',
    prev: [],
    next: [
      E('e1', 0, { num: 1, expr: '{nope}' }),
      E('e2', 0, { num: 2, expr: '{e1}+1' }),
      E('e3', 0, { num: 3, expr: '{sum}+1' }),
    ],
  },
  {
    name: 'division by a line that went to zero errors rather than going infinite',
    prev: [],
    next: [E('e1', 0, { num: 1 }), E('e2', 0, { num: 2, expr: '100÷{e1}' })],
  },
  {
    name: 'a forward reference resolves to nothing (unreachable through the UI)',
    prev: [],
    next: [E('e1', 0, { num: 1, expr: '{e2}+1' }), E('e2', 5, { num: 2 })],
  },
  {
    name: 'a plain line keeps its value even when it looks computed',
    prev: [],
    next: [E('e1', 15, { num: 1, expr: '60÷4' })],
  },
  {
    name: 'excluding a line changes every {sum} below it',
    prev: [
      E('e1', 10, { num: 1 }),
      E('e2', 4, { num: 2 }),
      E('e3', 14, { num: 3, expr: '{sum}' }),
    ],
    next: [
      E('e1', 10, { num: 1 }),
      E('e2', 4, { num: 2, excluded: true }),
      E('e3', 14, { num: 3, expr: '{sum}' }),
    ],
  },
  {
    name: 'reordering re-evaluates against the new order',
    prev: [E('e1', 10, { num: 1 }), E('e2', 20, { num: 2, expr: '{e1}×2' })],
    next: [E('e2', 20, { num: 2, expr: '{e1}×2' }), E('e1', 10, { num: 1 })],
  },
  {
    name: 'emptying the list',
    prev: [E('e1', 10, { num: 1 }), E('e2', 20, { num: 2, expr: '{e1}×2' })],
    next: [],
  },
  {
    name: 'deleting the middle of a chain freezes one link and keeps the other',
    prev: [
      E('e1', 10, { num: 1 }),
      E('e2', 20, { num: 2, expr: '{e1}×2' }),
      E('e3', 30, { num: 3, expr: '{e2}+{e1}' }),
    ],
    next: [E('e1', 10, { num: 1 }), E('e3', 30, { num: 3, expr: '{e2}+{e1}' })],
  },
  {
    name: 'a frozen negative value keeps the keypad minus',
    prev: [E('e1', -4.5, { num: 1 }), E('e2', 0, { num: 2, expr: '{e1}+10' })],
    next: [E('e2', 0, { num: 2, expr: '{e1}+10' })],
  },
  {
    name: 'notes and excluded flags survive a recompute untouched',
    prev: [],
    next: [
      E('e1', 4, { num: 1, note: 'People', excluded: true }),
      E('e2', 0, { num: 2, note: 'Each owes', expr: '{sum}÷{e1}' }),
      E('e3', 100, { num: 3, note: 'Dinner' }),
    ],
  },
];

// ---------------------------------------------------------------------------
// Randomised scenarios over the same grammar, so a rule the named list missed
// still has to agree. Seeded, so regenerating gives a reviewable diff.
let seed = 0x7a11;
const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
const pick = (a) => a[Math.floor(rnd() * a.length) % a.length];

function randomList(n, idPool) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const id = idPool[i];
    const above = idPool.slice(0, i);
    const r = rnd();
    if (r < 0.35 && above.length) {
      // a referencing line — only ever pointing at a line above it, the one
      // rule that makes cycles impossible
      const tok = rnd() < 0.3 ? '{sum}' : `{${pick(above)}}`;
      const expr = pick([`${tok}×2`, `${tok}÷2`, `${tok}+10`, `100−${tok}`, tok, `${tok}÷{missing}`]);
      out.push(E(id, 0, { expr, ...(rnd() < 0.1 ? { excluded: true } : null) }));
    } else {
      out.push(
        E(id, Math.round(rnd() * 20000) / 100, {
          ...(rnd() < 0.15 ? { excluded: true } : null),
          ...(rnd() < 0.5 ? { num: 1 + Math.floor(rnd() * 20) } : null),
        }),
      );
    }
  }
  return out;
}

const random = [];
for (let s = 0; s < 400; s++) {
  const pool = Array.from({ length: 8 }, (_, i) => 'e' + (100 + i));
  const prev = randomList(1 + Math.floor(rnd() * 6), pool);
  // `next` is `prev` with a few lines dropped, kept or shuffled — the shapes a
  // screen actually produces (delete, edit, reorder, append)
  let next = prev.filter(() => rnd() > 0.25).map((e) => ({ ...e }));
  if (rnd() < 0.3 && next.length > 1) next = [next[next.length - 1], ...next.slice(0, -1)];
  if (rnd() < 0.3) next.push(E('e' + (200 + s), Math.round(rnd() * 5000) / 100));
  if (rnd() < 0.2 && next.length) next[0] = { ...next[0], value: Math.round(rnd() * 900) / 10 };
  random.push({ name: `random #${s}`, prev, next });
}

const cases = [...SCENARIOS, ...random].map((s) => ({
  name: s.name,
  prev: s.prev,
  next: s.next,
  out: pipeline(s.prev, s.next),
}));

function render(f) {
  const head = (k, v) => `  ${JSON.stringify(k)}: ${JSON.stringify(v)}`;
  const rows = f.cases.map((c) => '    ' + JSON.stringify(c)).join(',\n');
  return `{\n${head('version', f.version)},\n  "cases": [\n${rows}\n  ]\n}`;
}

writeFileSync(OUT, render({ version: 1, cases }) + '\n');
console.log(`wrote ${cases.length} pipeline cases → ${OUT}`);
