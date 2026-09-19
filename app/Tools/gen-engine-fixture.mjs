// gen-engine-fixture.mjs — generates the golden fixture the Swift engine is
// tested against (TallyKit/Tests/TallyKitTests/Fixtures/engine.json).
//
// The Swift port of the calc engine decides what people's money adds up to, and
// several of its rules are non-obvious enough to get quietly wrong: unary minus
// carried as a flag through the token stream, iOS-style percent that means one
// thing after +/- and another everywhere else, a trailing operator dropped as
// incomplete, an unresolvable reference poisoning the whole expression rather
// than resolving to zero, and a hand-rolled `fmt` that must NOT become a
// NumberFormatter (Hermes' Intl varies by platform, which is why it was written
// by hand in the first place).
//
// So the expected values are not written by hand here — they are produced by
// running the original TypeScript engine, frozen at reference-engine/
// calc-engine.ts. That file is a verbatim copy of what mobile/ shipped; keep it
// frozen even after mobile/ is deleted, so the fixture stays reproducible.
//
//   node app/Tools/gen-engine-fixture.mjs
//
// Node strips the TypeScript types natively (24.x), so there is no build step.
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import * as Calc from './reference-engine/calc-engine.ts';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, '..', 'TallyKit', 'Tests', 'TallyKitTests', 'Fixtures', 'engine.json');

// ---------------------------------------------------------------------------
// The resolver every `evaluate` case runs against. Fixed, so the fixture is
// deterministic and the Swift test can build the same table literally.
//
// `e104` is zero (the division-by-a-zero-line path) and `e900` is deliberately
// absent — an unresolvable token, which must poison its whole expression.
const REFS = {
  sum: 12.5,
  e101: 10,
  e102: 2.5,
  e103: -4,
  e104: 0,
};
const resolve = (id) => (id in REFS ? REFS[id] : null);

// A line in error resolves to nothing even though it exists — same path as a
// missing id, kept separate because the store reaches it differently.
const NAMES = {
  sum: 'Σ total',
  e101: 'Rent',
  e102: 'Coffee',
  e103: 'Refund',
  e104: 'People',
};
const nameFor = (id) => NAMES[id] ?? '#?';

// ---------------------------------------------------------------------------
// Hand-picked cases: every branch of the engine worth naming, written out so a
// reviewer can read the intent rather than infer it from a random string.
const HAND = [
  // plain arithmetic
  '', ' ', '0', '7', '7.5', '.5', '00.50',
  '1+2', '9-4', '3*4', '12/4', '2×3', '12÷4', '10−3',
  // precedence: × ÷ fold first, then + − left to right
  '2+3×4', '2×3+4', '100-10×2', '1+2×3+4', '20÷4÷5', '2×3×4', '100÷10×2',
  // unary minus, including doubled
  '-5', '−5', '-5+3', '--5', '−−5', '3+-2', '3×-2', '3÷-2', '-0',
  // stray operators where a value belongs are dropped, '-' negates instead
  '+5', '×5', '÷5', '+-5', '×-5',
  // trailing / incomplete
  '5+', '5×', '5+-', '5.', '.', '+', '-',
  // iOS-style percent: after + or − it's relative to the previous value,
  // anywhere else it is /100
  '50%', '200+10%', '200-10%', '200×10%', '200÷10%', '10%+200', '5%%',
  '1+2+10%', '1+2×10%',
  // division by zero is not a number
  '5÷0', '5/0', '0÷0', '5÷{e104}',
  // references
  '{e101}', '{sum}', '{e900}', '{e101}+{e102}', '{sum}×2', '{e103}',
  '-{e101}', '−{e101}', '{e101}÷{e104}', '{e101}+{e900}', '{e900}×0',
  '65×{e102}', '{e101}−{e102}−{e103}', '{e101}+', '{e101}{e102}',
  // whitespace is not meaningful
  ' 1 + 2 ', '1 +2', '1+ 2',
  // things that are not expressions at all
  'abc', '{}', '{e}', '{e1', 'e101', '{SUM}',
];

// ---------------------------------------------------------------------------
// Generated cases: a wide sweep over the same grammar, so a rule the hand list
// missed still has to agree. Seeded LCG — the corpus is stable across runs, so
// regenerating produces a reviewable diff rather than a whole new file.
let seed = 0x7a11; // "tally"
const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
const pick = (a) => a[Math.floor(rnd() * a.length) % a.length];

const OPS = ['+', '−', '×', '÷', '-', '*', '/'];
const TERMS = [
  () => String(Math.floor(rnd() * 1000)),
  () => (rnd() * 100).toFixed(2),
  () => (rnd() * 10).toFixed(1),
  () => Math.floor(rnd() * 100) + '%',
  () => '{' + pick(['e101', 'e102', 'e103', 'e104', 'sum', 'e900']) + '}',
  () => '0',
];

function generate(n) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const terms = 1 + Math.floor(rnd() * 4);
    let s = rnd() < 0.15 ? '-' : '';
    for (let k = 0; k < terms; k++) {
      if (k > 0) s += pick(OPS);
      s += pick(TERMS)();
    }
    if (rnd() < 0.08) s += pick(OPS); // trailing operator
    out.push(s);
  }
  return out;
}

// ---------------------------------------------------------------------------
const exprs = [...HAND, ...generate(2000)];

// `evaluate` returns a JS double; JSON round-trips it exactly, and the Swift
// side compares with a tolerance far tighter than a cent (see EngineTests).
const cases = exprs.map((expr) => ({
  expr,
  value: Calc.evaluate(expr, resolve),
  refs: Calc.refsIn(expr),
  hasOperator: Calc.hasOperator(expr),
  segments: Calc.splitExpr(expr).map((s) => (s.type === 'text' ? { text: s.text } : { ref: s.id })),
  text: Calc.exprText(expr, nameFor),
}));

// `fmt` and `plain` are separate tables — they take a number, not an expression.
//
// The `.xx5` values are not padding. JS `toFixed` is specified to round on the
// *exact* binary value, ties away from zero (0.125 → "0.13"), while C's
// `printf("%.2f")` rounds ties to even (0.125 → "0.12"). So the Swift port must
// not reach for `String(format:)`; these cases are what catches it if it does.
const TIES = [0.125, 0.375, 0.625, 0.875, 1.125, 2.125, -0.125, -2.125, 8.835];
const NUMBERS = [
  0, -0, 1, -1, 0.5, -0.5, 0.004, 0.005, 0.006, -0.005, 1.005, 2.675,
  ...TIES,
  999.99, 999.999, 1000, -1000, 1234.5, 12345.678, 999999.994, 999.995, 1e6, -1e6,
  1234567.891, 1e9, 1e12, 1e15, 1e21, 0.1 + 0.2, 1 / 3, -1 / 3,
  Number.MAX_SAFE_INTEGER, Number.EPSILON, Infinity, -Infinity, NaN,
];

/**
 * Known, deliberate divergences from the TypeScript original — the Swift port
 * is *not* expected to match these, and the test skips them by value.
 *
 * `1e21`: `toFixed` switches to exponential notation at 1e21, so `fmt` splits
 * "1e+21" on "." , gets `undefined` for the fractional part and returns the
 * string "1e+21.undefined". A real bug, unreachable in a running-tab app (it
 * would need a line in the sextillions) and never worth a fix in JS. Swift's
 * port formats it properly instead. Kept in the table so the divergence is
 * recorded rather than quietly absent.
 */
const DIVERGENT = [1e21];

const numbers = NUMBERS.map((n) => ({
  // Infinity/NaN have no JSON representation — carry them as tagged strings and
  // rebuild them on the Swift side.
  n: Number.isFinite(n) ? n : String(n),
  fmt: Calc.fmt(n),
  plain: Number.isFinite(n) ? Calc.plain(n) : null,
  ...(DIVERGENT.includes(n) ? { divergent: true } : null),
}));

const fixture = {
  // Bumped whenever the shape below changes, so a stale fixture fails loudly
  // instead of silently under-testing.
  version: 1,
  generatedFrom: 'app/Tools/reference-engine/calc-engine.ts',
  refs: REFS,
  names: NAMES,
  cases,
  numbers,
};

// Written with one case per line rather than fully pretty-printed: the file is
// reviewed as a diff more often than it is read, and a changed rule should show
// up as a handful of changed lines instead of a rewrite of the whole file.
function render(f) {
  const head = (k, v) => `  ${JSON.stringify(k)}: ${JSON.stringify(v)}`;
  const rows = (k, arr) =>
    `  ${JSON.stringify(k)}: [\n${arr.map((x) => '    ' + JSON.stringify(x)).join(',\n')}\n  ]`;
  return [
    '{',
    [
      head('version', f.version),
      head('generatedFrom', f.generatedFrom),
      head('refs', f.refs),
      head('names', f.names),
      rows('cases', f.cases),
      rows('numbers', f.numbers),
    ].join(',\n'),
    '}',
  ].join('\n');
}

writeFileSync(OUT, render(fixture) + '\n');
console.log(`wrote ${cases.length} expression cases + ${numbers.length} number cases → ${OUT}`);
