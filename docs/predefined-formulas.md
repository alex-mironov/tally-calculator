# Predefined formulas — investigation

*10 Aug 2026. Status: investigation only, nothing built. Written alongside the
tally-share Worker (`worker/`), which several options below lean on.*

## What a "formula" is in Tally's model

The calc engine is deliberately tiny: flat expressions (`+ − × ÷`, decimals,
iOS-style `%`), plus two reference tokens — `{e123}` (another line's value)
and `{sum}` (the running subtotal). No parens, no functions, no variables.

That turns out to be enough for a useful formula system **without touching the
engine**, because a formula is just a *template tab*:

- **input lines** — plain values with meaningful notes ("Bill", "People")
- **derived lines** — expressions referencing the inputs
  ("Tip 15%" = `{bill}×0.15`, "Per person" = `{sum}÷{people}`… almost)

Worked examples that fit today's engine:

| Formula | Lines |
|---|---|
| Tip & split | Bill · `Tip 15% = {bill}×0.15` · `Per person = {sum}×0.25` |
| VAT / sales tax | Net · `VAT 20% = {net}×0.2` |
| Discount | Price · `−20% = {price}×0.2` as a negative line |
| Trip kitty | N spend lines · `Each owes = {sum}×0.33` |
| Unit price ×qty | Rate · `Hours ×12 = {rate}×12` |

The seams show exactly where the engine stops:

1. **No division by a reference-derived count that changes** — "split by N"
   bakes N into the expression (`×0.25`), so changing the headcount means
   editing every derived line. A `÷{people}` works today, but `{sum}` includes
   the People line itself unless it's placed below — subtle, template-authoring
   footgun rather than blocker.
2. **No parens / pow** — rules out compound interest, loan payments, anything
   nonlinear. That's a real engine project (tokenizer + precedence already
   exist; parens are a contained addition, `pow` and functions are scope creep
   to resist until asked for).

## Where formulas could live — three options

**A. Bundled catalog (in the app).** A JSON list of template tabs shipped with
the app, surfaced as "New from formula…". Offline, zero infra, versioned with
app releases. Con: updating the catalog means shipping a build.

**B. Server catalog (on the Worker).** `GET /api/formulas` from KV, cached
locally, same snapshot format the share API already uses. Updatable any time,
one more KV namespace, no auth needed (read-only). Con: first-run needs
network; a catalog that changes weekly is a solution looking for a problem.

**C. User templates via the share pipeline.** This is the cheap, high-leverage
one: a share snapshot *is* a template — immutable, referenced-linked, and (as
of today) importable. Two small features fall out almost for free:

- **"Use as template"** on a saved tab: duplicate it locally (the
  `remapEntries` + `importTab` machinery from the share work does this
  verbatim) and let the user overwrite the input lines.
- **Shareable formulas**: any share link someone posts is already a formula
  others can import and refill. A `kind: "template"` flag on the payload could
  later make the share page and import flow say "template" instead of
  "snapshot" — cosmetic, not structural.

## Recommendation

Phase 1 — **C-lite**: "Duplicate as new" / "Use as template" on saved tabs.
~1 screen-day; reuses import machinery; validates whether templates get used
at all before any catalog exists.

Phase 2 — **A**: a curated bundled catalog (5–8 formulas from the table
above) behind "New from formula…" in the More menu, each opening as an
unsaved tab with the input lines ready to edit. The catalog file doubles as
the spec for what the engine can't express yet.

Phase 3 — **B, only if the catalog needs to move faster than releases**, and
by then it's a ~50-line addition to the existing Worker.

Engine work (parens first) should be driven by concrete formulas people ask
for, not built speculatively.

## Open questions

- Input ergonomics: how does a template *mark* which lines are inputs? Options:
  a convention (lines with value 0), or an `input: true` flag on the entry —
  the flag is cleaner and harmless to old payloads.
- Currency/percent display: formulas make mixed units more likely; today
  everything renders as 2dp money-ish. Probably fine to ignore for v1.
- Should the share page render a template differently (e.g. "fill in the
  bill")? Only matters once `kind: "template"` exists.
