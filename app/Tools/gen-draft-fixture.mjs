// gen-draft-fixture.mjs — golden fixture for the keypad's effect on the draft
// (TallyKit/Tests/TallyKitTests/Fixtures/draft.json).
//
// The draft string is what the engine is eventually handed, so a keypress rule
// that drifts produces a *valid expression that is the wrong one* — the worst
// failure mode available here. The rules are small but none of them are
// guessable:
//
//   · backspace deletes a whole `{e123}` pill, never its last character;
//   · an operator typed onto a trailing operator replaces it, except on an
//     empty draft, where only '−' survives (as a unary minus);
//   · '%' is ignored unless the draft ends in a digit;
//   · '.' looks at the current *term*, not the whole draft, and is ignored
//     after a pill (a pill is a finished number) or a term that already has
//     one; on an empty draft it types "0.";
//   · a digit straight after a pill starts a new term, joined with '+'.
//
// Expected values come from running the original TypeScript, frozen under
// reference-engine/draft.ts.
//
//   node app/Tools/gen-draft-fixture.mjs
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { applyKey, draftFontSize, draftLength, insertRef } from './reference-engine/draft.ts';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, '..', 'TallyKit', 'Tests', 'TallyKitTests', 'Fixtures', 'draft.json');

const KEYS = [
  '⌫', 'AC', '%', '÷',
  '7', '8', '9', '×',
  '4', '5', '6', '−',
  '1', '2', '3', '+',
  'ref', '0', '.', '↵',
];

// Drafts worth starting from: every shape the rules distinguish.
const DRAFTS = [
  '',
  '0',
  '7',
  '12',
  '12.',
  '12.5',
  '12.50',
  '0.',
  '−',
  '−5',
  '5+',
  '5+3',
  '5+3.',
  '5.5+3.5',
  '5×',
  '5÷',
  '5−',
  '100−20',
  '{e101}',
  '{sum}',
  '{e101}+',
  '{e101}+2',
  '{e101}×3',
  '{e101}+{e102}',
  '2+{e101}',
  '{e101}.',
  '12%',
  '5+10%',
  '1234567890',
  '1+2+3+4+5',
];

// Every draft × every key, which is the whole rule table rather than a sample.
const cases = [];
for (const d of DRAFTS) {
  for (const k of KEYS) {
    cases.push({ draft: d, key: k, out: applyKey(d, k) });
  }
}

// Sequences, because the rules compose — and because this is how a real line is
// typed. Each records the draft after every keystroke.
const SEQUENCES = [
  { name: 'a plain amount', keys: ['4', '2', '.', '2', '0'] },
  { name: 'a split bill', keys: ['6', '0', '÷', '4'] },
  { name: 'backspacing through a decimal', keys: ['1', '2', '.', '5', '⌫', '⌫', '⌫'] },
  { name: 'operator replacement', keys: ['5', '+', '−', '×', '÷', '3'] },
  { name: 'leading minus', keys: ['−', '4', '.', '5'] },
  { name: 'percent needs a digit', keys: ['%', '2', '0', '%', '%'] },
  { name: 'a second decimal point is ignored', keys: ['1', '.', '5', '.', '5'] },
  { name: 'a decimal in the second term', keys: ['1', '.', '5', '+', '2', '.', '7', '5'] },
  { name: 'dot on an empty draft types a leading zero', keys: ['.', '5'] },
  { name: 'minus on an empty draft is unary', keys: ['−', '−'] },
  { name: 'other operators on an empty draft do nothing', keys: ['+', '×', '÷', '7'] },
];

const sequences = SEQUENCES.map((s) => {
  let d = '';
  const steps = s.keys.map((k) => {
    const next = applyKey(d, k);
    if (next != null) d = next;
    return { key: k, draft: d };
  });
  return { name: s.name, keys: s.keys, steps };
});

// Reference insertion, from each of the draft shapes above.
const inserts = [];
for (const d of DRAFTS) {
  for (const id of ['e101', 'sum']) {
    inserts.push({ draft: d, id, out: insertRef(d, id) });
  }
}

// Backspacing a pill out is the rule most likely to be got wrong, so it gets
// its own table: a pill must go whole.
const backspace = [
  '{e101}', '{sum}', '2+{e101}', '{e101}+2', '{e101}{e102}', '{e1010}',
  '{e101}%', '{notapill}', '{e101', 'e101}', '}', '{',
].map((d) => ({ draft: d, out: applyKey(d, '⌫') }));

// The draft's rendered length and the one size step it drives. Names are what
// the pill actually draws, not the token.
const NAMES = { sum: 'Σ total', e101: 'Rent', e102: 'A rather long note here' };
const nameFor = (id) => NAMES[id] ?? '#?';
const sizes = [
  '', '0', '1234', '12345678901', '123456789012', '1234567890123456',
  '{e101}', '{sum}', '{e102}', '{e101}+{e101}', '1+{e102}',
].map((expr) => ({
  expr,
  length: draftLength(expr, nameFor),
  size: draftFontSize(draftLength(expr, nameFor)),
}));

function render(f) {
  const head = (k, v) => `  ${JSON.stringify(k)}: ${JSON.stringify(v)}`;
  const rows = (k, arr) =>
    `  ${JSON.stringify(k)}: [\n${arr.map((x) => '    ' + JSON.stringify(x)).join(',\n')}\n  ]`;
  return [
    '{',
    [
      head('version', f.version),
      head('names', f.names),
      rows('cases', f.cases),
      rows('sequences', f.sequences),
      rows('inserts', f.inserts),
      rows('backspace', f.backspace),
      rows('sizes', f.sizes),
    ].join(',\n'),
    '}',
  ].join('\n');
}

writeFileSync(
  OUT,
  render({ version: 1, names: NAMES, cases, sequences, inserts, backspace, sizes }) + '\n',
);
console.log(
  `wrote ${cases.length} key cases, ${sequences.length} sequences, ${inserts.length} inserts → ${OUT}`,
);
