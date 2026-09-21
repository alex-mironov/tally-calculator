// check-web-format.mjs — holds the web share page to the same golden fixture as
// the Swift app.
//
//   node app/Tools/check-web-format.mjs
//
// A shared tab is rendered twice: in the app that made it, and on the web page
// (web/src/lib/format.ts) that anyone with the link opens. The two must agree,
// and until this script only the Swift half was tested. The web page has no
// `evaluate` — it only displays values the app already computed — so what can
// drift is number formatting, how an expression splits into text and reference
// pills, and whether a line's workings are shown at all. Each is checked
// against the fixture generated from the original TypeScript engine.
//
// Exits non-zero on any disagreement, so it can sit in CI.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import * as Web from '../../web/src/lib/format.ts';

const HERE = dirname(fileURLToPath(import.meta.url));
const fixture = JSON.parse(
  readFileSync(join(HERE, '..', 'TallyKit', 'Tests', 'TallyKitTests', 'Fixtures', 'engine.json'), 'utf8'),
);

let failures = 0;
const fail = (what, input, got, want) => {
  failures++;
  if (failures <= 20) console.log(`✘ ${what}(${JSON.stringify(input)}): got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
};

// ── fmt ────────────────────────────────────────────────────────────────────
// Including the rows the Swift port deliberately diverges on: the web page
// shares the *original's* behaviour, so it is held to the original there.
for (const row of fixture.numbers) {
  const n = typeof row.n === 'string' ? Number(row.n) : row.n;
  const got = Web.fmt(n);
  if (got !== row.fmt) fail('fmt', row.n, got, row.fmt);
}

// ── splitExpr: the same text runs and the same reference ids ───────────────
for (const c of fixture.cases) {
  const got = Web.splitExpr(c.expr, []).map((s) => (s.type === 'text' ? { text: s.text } : { ref: s.id }));
  if (JSON.stringify(got) !== JSON.stringify(c.segments)) fail('splitExpr', c.expr, got, c.segments);
}

// ── showExpr: a line shows its workings when it has an operator or a reference
for (const c of fixture.cases) {
  if (!c.expr) continue;
  const want = c.hasOperator || c.refs.length > 0;
  const got = Web.showExpr({ id: 'x', note: '', expr: c.expr, value: 0 });
  if (got !== want) fail('showExpr', c.expr, got, want);
}

const checked = fixture.numbers.length + fixture.cases.length * 2;
if (failures) {
  console.log(`\n${failures} disagreement(s) between web/src/lib/format.ts and the engine fixture.`);
  process.exit(1);
}
console.log(`✔ web/src/lib/format.ts agrees with the engine fixture (${checked} checks).`);
