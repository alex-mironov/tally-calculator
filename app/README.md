# app/ — Tally, native

The SwiftUI rewrite. See [`../docs/swiftui-rewrite.md`](../docs/swiftui-rewrite.md)
for the plan this is working through, and what it replaces.

iOS 26 and up, iPhone and iPad. `../mobile/` (Expo / React Native) stays in
place and runnable until the cutover in Phase 6 — until then, both build.

```
TallyKit/          Swift package: everything Tally knows how to do, no UI
  Sources/
    Calc.swift       the expression engine
    Models.swift     Entry, Tab, tag names — and their JSON contract
    Pipeline.swift   the live-reference pass
    Accents.swift    the accent palette, as data (hex, not Color)
    Storage.swift    local cache mirrored to the iCloud key-value store
    TallyStore.swift the @Observable the whole app reads
  Tests/
    Fixtures/        golden fixtures, generated (see below)
Tools/
  reference-engine/  FROZEN copies of the TypeScript originals
  gen-*-fixture.mjs  the generators
```

`Accents.swift` holds hex strings rather than `Color` on purpose: the store has
to resolve a persisted accent on hydration — including hexes from palettes the
app has since retired — so the palette data belongs below the UI. Turning it
into `Color` is the app layer's job.

## Running the tests

```bash
cd app/TallyKit && swift test
```

No simulator needed — TallyKit has no UI in it, which is the point of it being
a package rather than a folder in the app target.

## The fixtures, and why they exist

Three things in here decide what people's money adds up to: the expression
engine, the reference pipeline, and the JSON the two are persisted and shared
as. All three have to agree with the React Native build *exactly* — not
approximately — because:

- the iCloud key-value store is **shared** between the two apps, so mid-rollout
  a user may have the old build on one device and this one on another;
- the share API is frozen, and the web share page re-renders the same
  expressions from the same payload;
- people have saved tabs whose numbers were produced by the original's quirks.

So none of the expected values in the test suites are written by hand. Each
generator runs the *original TypeScript*, frozen under `Tools/reference-engine/`,
over a corpus and commits the result:

```bash
node Tools/gen-engine-fixture.mjs     # ~2,100 expressions + 44 numbers
node Tools/gen-pipeline-fixture.mjs   # 422 (prev, next) scenarios
node Tools/gen-models-fixture.mjs     # the persisted/wire key sets
```

They are seeded and emit one case per line, so regenerating produces a
reviewable diff rather than a new file. **Keep `Tools/reference-engine/` frozen
even after `mobile/` is deleted** — it is what makes the fixtures reproducible.

### What the fixtures have already caught

Each of these was found by a mutation test against the suite, and each would
have been a silent wrong number rather than a crash:

- **`String(format: "%.2f")` is the wrong rounding.** C rounds halves to even,
  so it turns `0.125` into `"0.12"`; JavaScript's `toFixed` rounds halves away
  from zero and gives `"0.13"`. `Calc.fmt` rounds on the decimal expansion by
  hand for this reason.
- **`Double.rounded()` is not `Math.round`.** JavaScript rounds halves toward
  +∞, Swift rounds them away from zero — they disagree on every negative half,
  so `Calc.plain` uses `floor(x + 0.5)`. (This is also why `plain(-0.125)` is
  `"−0.12"` while `fmt(-0.125)` is `"−0.13"`. Both are faithful.)
- **Synthesised `Codable` writes `"excluded": false`.** The original writes
  `excluded` and `error` only when true — *counted* is the absence of the key —
  so `Entry`'s coding is hand-written and `ModelsTests` holds it there.

### The one deliberate divergence

`fmt(1e21)`. JavaScript's `toFixed` switches to exponential at 1e21, and the
original then splits `"1e+21"` on `"."`, gets `undefined` for the fraction and
returns the string `"1e+21.undefined"`. Unreachable in a running-tab app and
never worth fixing in JS; this formats it properly instead. The fixture marks
the case `divergent` so the difference is recorded rather than quietly absent.
