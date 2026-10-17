# Calculator v2 — "tonal monochrome"

The design handoff `Calculator-handoff.zip` (Claude Design, Oct 2026) replaces the
v1 "Current build" board the app was matched to. Source of truth, in order:
`tally-app-v2.jsx` (SCHEMES, layout, states) › `tally-saved-r.jsx`,
`tally-settings-r.jsx`, `tally-tags.jsx` › `tokens.css`. `Design System v2.html`
is stale (Spline Sans Mono, pink accent) and is not followed.

> One mood colour fills the screen; colour is never sprinkled. One dominant
> number (the total), rows sit on the canvas, and every input lives in one
> floating dock in the thumb zone. Pills and circles only, radii concentric
> with the device.

## Decisions (12 Oct 2026)

| Question | Decision |
|---|---|
| Fonts | **SF everywhere** — the design's own "SF Pro" Tweak. Numbers, keys, total, draft and amounts use SF with tabular digits at the weights v2 gives Urbanist; UI text is SF. Nothing bundled; Geist is retired. |
| Light/Dark | **Dropped.** The scheme decides darkness; only Midnight is dark. Settings shows four scheme swatches. |
| Keys & dock | **Opaque**, per v2: one opaque dock, pill keys with a press fill. Glass only on floating chrome (bar buttons, toasts). |
| Title/menu | Per the design's header (revised 17 Oct 2026): tray and a filled "+" (`.glassProminent` tinted `deep`) together on the leading edge, the calculation's name + chevron as a native trailing `Menu` bar item; the system title is removed except in select mode ("N selected"). Native bar items, no drawn pills. Landscape iPad: the name menu only. |
| App extras v2 omits | Kept: "Don't count in total", Share link…. The sticky line `num` is still stored, but no longer shown (see Links below). |
| Reference model | Superseded 17 Oct 2026 — see "Links and brackets". |
| 4pt grid | Off-grid design values are rounded onto it, or commented where they can't be. |
| iPad modes | By **window width**, not orientation: ≥ 1024 landscape (sidebar), 700–1023 portrait (overlay Saved, centred 560pt dock, 58pt keys), < 700 phone. |
| Typing | Typing on the keypad is unanimated: no per-key transitions (user, 12 Oct 2026). The draft's size steps, the entry row's result, the operator key inverting and the hero all land outright; a key's press fill is instant in and 0.1s out. The shake on a refused commit, the stow slide and the toasts are not typing, and keep their motion. |

## Links and brackets (handoff of 17 Oct 2026)

The second handoff (`tally-links.jsx`, plus the link/brackets states in
`tally-app-v2.jsx`) reworks references into **links** and adds brackets.
Schemes, Saved, Settings and Tags are otherwise unchanged.

| Area | Built as |
|---|---|
| Link mode | The link key starts it; the pad folds to `123 + − × ÷ ↵` (`Key.linkBar`). Tapping a line above links it, tapping again unlinks it with its joining operator (`Draft.toggleRef`); the mode stays on until "123", a digit from a keyboard, Esc or a commit. Pickable rows grow a 32pt link circle → cta tick once linked; the rest dim to 0.32; the line being edited reads "Link lines above this one". Hero label "Tap lines to link them"; the total is no longer linkable (old `{sum}` data still evaluates). The bar shows even with the keys stowed. |
| Badges | Links are drawn as the linked line's **position** in a circle: quiet (chip/ink2) in a row's workings, solid where it is the line being edited; in the draft a 36pt op pill = inverse badge + note + value. Unnamed lines read "Line <position>", so title and badge agree. |
| Rows | Position circle 32pt, chip/ink2; deep while editing (was deep, cta while editing). |
| Delete in use | Deleting a line others link asks first (`ConfirmDeleteSheet`, a fitted sheet / 420pt form sheet): "Delete ④ Taxi? It's linked in ⑤ Taxi tip, which will keep 1.82 as a fixed number." A plain delete stays one swipe + Undo. The swipe action is tinted red rather than `role: .destructive` — the role makes List drop the row before the data does, which crashed once the delete could wait on a sheet. |
| Ripple toast | A commit that moves lines built on it says "Updated ⑤ Taxi tip" / "Updated N linked lines" (1.5s), after Total copied and Undo in precedence. |
| Brackets | `Calc.evaluate` takes brackets (each level evaluated by the original flat rules, so bracket-free maths is unchanged and the fixtures still pass); open brackets auto-close, an empty one is dropped, a stray `)` is nil. Settings → "Brackets key" (`bracketsKey` in `tally:config`, absent ≠ off) puts "( )" in AC's place; hold ⌫ clears. Open brackets ghost after the caret; commits are `Draft.normalized`. Keyboard `(` `)` always work; `#` is the link key. |
| Group first | When × or ÷ follows a top-level sum, a tonal chip above the entry row offers "Group first → value" (`Draft.groupedFirst`); afterwards "Ungroup". |
| Context menu | Edit, Select, **Link in new line** (a fresh draft of just that link), Don't count in total, —, Delete. |

## Schemes

Hex data in TallyKit (`Scheme.swift`), mapped to `Color` in `Theme.swift`. Full
token sets are in `tally-app-v2.jsx:12-41`. Highlights:

| | screen | ink | cta / ctaInk | op / opInk | dock |
|---|---|---|---|---|---|
| Midnight (dark) | #000000 | #ffffff | #e6fc7c / #0a0a0a | #cbd5e3 / #0a0a0a | #1c1c1e |
| Lilac | #e3abe2 | #1f0d1d | #5e2a59 / #ffffff | #f4dff3 / #5e2a59 | #ffffff |
| Sand | #f3e5cf | #1d160e | #1d160e / #ffffff | #f1e5d2 / #1d160e | #ffffff |
| Paper | #ffffff | #0b0b0c | #0b0b0c / #ffffff | #ffffff / #0b0b0c | #f4f4f5 |

`legacy(S)` (`tally-app-v2.jsx:43-45`) maps schemes onto the old theme names:
accent = cta, accent2 = chipBg, accentInk = accentText, onAccent = ctaInk.
The iPad sheet surface in Midnight is elevated: screen #1c1c1e, card #2c2c2e,
field #3a3a3c, line #38383a (`tally-app-v2.jsx:202`). No accent bloom anywhere.

**Migration.** The scheme persists under its own storage key (`tally:scheme`),
not inside `tally:config` — an older build re-encoding `ConfigDocument` would drop
an unknown field. With no scheme stored: Lime, or any dark mode → Midnight;
Violet family (incl. retired hexes resolving to it) light → Lilac; Blue light →
Paper; nothing stored → Midnight. Writes keep a best-effort `accent`/`themeMode`
in `tally:config` for older builds (Midnight → Lime/dark, Lilac → Violet/light,
Sand/Paper → Blue/light). The frozen share API still receives an `accent` hex.

## Gaps, by area

**iPhone calculator** (`tally-app-v2.jsx`)
- Header: tray + new + title menu (`:391-406`). Menu: Rename…, Tags…, Copy total, Share link…, Select lines, —, Saved (n), Settings (`:378-386`).
- Hero total at the top: "Total" + copy circle; Urbanist 500 at 60/52/44/38 by length, rolling digits; tap copies with a "Total copied" toast above the dock. (The earlier board's "+42.80 last · 4 lines" sub-line is gone from the design and from the app.)
- Rows on the canvas (`:128-152`): hairlines, 64 min height, 40pt position circle (deep; cta while editing), 16pt medium note, unnamed → "Line N", 14pt ink2 workings, Urbanist 17 amount. Swipe → 52pt red circular delete.
- Empty state bottom-left: "Start a tally." / "Type an amount, add a note, then tap return. Lines stack up here." (`:426-429`).
- One opaque dock (`:349`, radius 40, 2pt cta ring while editing): grabber (tap toggles), entry row (outline note chip, "= preview" or "Total ‹new›", Cancel while editing), draft (Urbanist 400 at 46/38/31/26, left fade, caret, shake on invalid, horizontal swipe deletes a char per 28pt), keys.
- Keys (`:366-375`): 48pt pills, gap 8, Urbanist 27; tonal operators, the active trailing operator inverts; AC/% SF 18 dockInk2; link key outlined, cta + ✕ while active, 0.35 with no lines; ↵ the one cta key. Fire on touch-down; hold ⌫ 480ms clears.
- Link mode (`:340-341`): hero label "Tap the total or a line to link it", rows show op-filled link circles; token pill op fill, radius 12.
- Select (`:391-442`): header Select all / "N selected" / ✓; outlined → cta check circles; dock replaced by footer "N of M" + rolling subtotal.
- Context menu: Edit, Select, Use as reference, Don't count in total, —, Delete. Undo toast "Line deleted · Undo" 4.5s + ⌘Z. Note suggestions (≤3 recent notes by prefix). Letters on a hardware keyboard start a note.
- Rename sheet name-only (✕ / "Rename" / ✓, placeholder today's date, "Leave blank to use today's date."). Tags… opens the Tags page as a picker sheet.

**Saved / Settings / Tags** (iPhone)
- Settings: four scheme swatches ("Colour scheme"), no Theme row; `.listRowBackground(t.card)`; headers ink2.
- Saved: type sizes (name 17/500, meta 14), draft card radius 20 in accent2, Save pill cta/ctaInk; empty state with a ghost stack of three cards, title 28/400 ink2, sub 17, tonal CTA; delete confirmation ("Delete “X”? This can't be undone."); Edit tags as a sheet.
- Tags page: section headers 19/600 ink, A–Z index rail with ★, search on demand.

**iPad**
- Landscape: no sidebar toggle; title menu only; hero heads the main column; dock 400pt, radius 40, 16 inset, no grabber.
- Portrait: single column; Saved as a 360pt leading overlay, scrim 0.6 dark / 0.26 light, closes on open/new; tray + new on the left; dock centred `min(560, w−48)`, 58pt keys (radius 29), grabber.
- Settings and Tags as ~540pt form sheets (Manage tags pushes inside Settings); Edit tags from a saved row via long-press → form sheet. Sidebar flat screen colour + 1px line.
