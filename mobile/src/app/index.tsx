// index.tsx — Tally, the running-tab calculator (2026 refresh). One screen:
// a nameable tab, a labelled list of amounts, a live total, the in-progress
// entry, optional tag chips, and the keypad. The ⋯ menu opens the Saved
// archive and Settings.
//
// The keypad is ~360pt — around 40% of the screen — so it can be stowed to give
// the list that space back: drag the grabber above the total down, or tap it.
// See "keypad avoidance" below; stowing and the system keyboard share one
// collapse path so they can't fight each other.
import { Button, Divider, Host, Image, List, Menu, Section } from '@expo/ui/swift-ui';
import {
  accessibilityLabel,
  contentShape,
  frame,
  listRowSpacing,
  listSectionSpacing,
  listStyle,
  scrollContentBackground,
  shapes,
  tint,
} from '@expo/ui/swift-ui/modifiers';
import * as Clipboard from 'expo-clipboard';
import { GlassView, isLiquidGlassAvailable } from 'expo-glass-effect';
import { useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  findNodeHandle,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
  type TextInput as RNTextInput,
} from 'react-native';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, {
  Easing,
  FadeIn,
  runOnJS,
  useAnimatedKeyboard,
  useAnimatedReaction,
  useAnimatedStyle,
  useSharedValue,
  withSequence,
  withTiming,
} from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Keypad, type Key } from '@/components/tally/keypad';
import { SaveSheet } from '@/components/tally/save-sheet';
import { ScreenBackground } from '@/components/tally/screen-bg';
import { SwipeRow } from '@/components/tally/swipe-row';
import { TagToggleGlass } from '@/components/tally/tag-glass';
import { TallyFonts } from '@/constants/tally-theme';
import { Elevation } from '@/constants/tokens';
import * as Calc from '@/lib/calc-engine';
import * as Haptic from '@/lib/haptics';
import { uid, useTally, type Entry, type Tab } from '@/lib/tally-store';
import { scrollListToEnd } from '../../modules/list-scroll';

// iOS 26+ renders the entry card as native Liquid Glass; older OS keeps the
// opaque card. Resolved once at module load.
const LIQUID = isLiquidGlassAvailable();

// HIG minimum tap target, shared by the ⋯ host and its SwiftUI label so the
// two can't drift apart. MENU_BLEED is half the slack between the 22pt glyph and
// that target — the amount the box has to hang past the content margin to keep
// the dots looking flush with it.
const MENU_HIT = 44;
const MENU_BLEED = 10;

// Keypad stow/restore. Settling is deliberately not a spring: the keypad is a
// large surface and overshoot on ~360pt of travel reads as a bounce, not as
// physics. Past halfway — or a decisive flick — commits, the usual sheet rule.
const PAD_SETTLE = { duration: 260, easing: Easing.out(Easing.cubic) };
const PAD_FLING = 500;

// Worklet twin of Calc.fmt so the count-up can format on the UI thread (regex
// isn't worklet-safe, so the thousands grouping is a manual loop).
function fmtTotal(n: number): string {
  'worklet';
  if (n == null || !isFinite(n)) return '0.00';
  const neg = n < 0;
  const fixed = Math.abs(n).toFixed(2);
  const dot = fixed.indexOf('.');
  const whole = fixed.slice(0, dot);
  const frac = fixed.slice(dot + 1);
  let grouped = '';
  let count = 0;
  for (let i = whole.length - 1; i >= 0; i -= 1) {
    grouped = whole.charAt(i) + grouped;
    count += 1;
    if (count % 3 === 0 && i > 0) grouped = ',' + grouped;
  }
  return (neg ? '−' : '') + grouped + '.' + frac;
}

// The running total, animated: a count-up tween whenever the value changes plus
// a subtle scale pulse to draw the eye. Isolated in its own component so the
// per-frame text updates don't re-render the whole screen.
function AnimatedTotal({ value, color }: { value: number; color: string }) {
  const tv = useSharedValue(value);
  const pulse = useSharedValue(1);
  const [text, setText] = useState(() => Calc.fmt(value));
  const first = useRef(true);

  useEffect(() => {
    if (first.current) {
      first.current = false;
      tv.value = value;
      setText(Calc.fmt(value));
      return;
    }
    tv.value = withTiming(value, { duration: 420, easing: Easing.out(Easing.cubic) });
    pulse.value = withSequence(
      withTiming(1.06, { duration: 110, easing: Easing.out(Easing.quad) }),
      withTiming(1, { duration: 220, easing: Easing.out(Easing.quad) }),
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value]);

  useAnimatedReaction(
    () => tv.value,
    (v) => runOnJS(setText)(fmtTotal(v)),
  );

  const pulseStyle = useAnimatedStyle(() => ({ transform: [{ scale: pulse.value }] }));

  return (
    <Animated.Text style={[styles.tBig, { color }, pulseStyle]} maxFontSizeMultiplier={1.4}>
      {text}
    </Animated.Text>
  );
}

export default function TallyScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const {
    entries,
    setEntries,
    total,
    theme: t,
    themeMode,
    showExpr,
    showTotal,
    tabs,
    activeId,
    tabName,
    tags,
    setTags,
    catalog,
    addCatalogTag,
    newTab,
  } = useTally();

  const [draft, setDraft] = useState('');
  const [note, setNote] = useState('');
  const [noteOpen, setNoteOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [flash, setFlash] = useState(false);
  const [copied, setCopied] = useState(false);
  const [saveOpen, setSaveOpen] = useState(false);

  const noteInputRef = useRef<RNTextInput>(null);

  useEffect(() => {
    if (noteOpen) noteInputRef.current?.focus();
  }, [noteOpen]);

  // ---- keep the newest row in view ----
  // With the keypad up the list shows only a handful of rows, so a committed
  // entry lands below the fold and the user never sees it arrive. SwiftUI has
  // no bridge-reachable scroll API for `List` (scrollPosition is ScrollView-
  // only), so the ListScroll native module scrolls the UICollectionView behind
  // the Host instead — see modules/list-scroll. The short delay gives SwiftUI
  // a beat to insert the row before "the end" is measured; the second nudge
  // catches slow row layouts without being noticeable when the first landed.
  // `justAddedId` also drives the row's one-shot highlight flash, then clears
  // once the flash has run its course.
  const listWrapRef = useRef<View>(null);
  const [justAddedId, setJustAddedId] = useState<string | null>(null);

  useEffect(() => {
    if (!justAddedId) return;
    const scroll = () => scrollListToEnd(findNodeHandle(listWrapRef.current));
    const t1 = setTimeout(scroll, 80);
    const t2 = setTimeout(scroll, 320);
    const t3 = setTimeout(() => setJustAddedId(null), 1400);
    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
      clearTimeout(t3);
    };
  }, [justAddedId]);

  // ---- keypad avoidance (HIG "Virtual keyboards": keyboard layout guide) ----
  // Two things want the keypad out of the way, and they share one collapse so
  // they can never fight over the same height:
  //
  //   · the system keyboard. Text entry here — the ✎ note, the inline "new tag"
  //     field — used to raise it straight over the keypad, burying the very
  //     field being typed into. The keypad is dead weight while a keyboard is
  //     up, so it collapses in step with the keyboard's rise and a spacer of
  //     exactly the keyboard's height takes its place.
  //   · the user, stowing it by hand to read a long tab (see PAD_* below).
  //
  // Whichever wants it shut further wins (`Math.max`), so stowing the pad while
  // the keyboard is up — or dismissing the keyboard while stowed — never pops
  // the keypad back into view. Driven on the UI thread so both track their
  // input frame-for-frame instead of snapping.
  const keyboard = useAnimatedKeyboard();
  const [padHeight, setPadHeight] = useState(0);
  // 0 = keypad up, 1 = fully stowed. Intermediate values are the live drag.
  const stow = useSharedValue(0);
  const stowStart = useSharedValue(0);
  // JS mirror of `stow`'s resting state — drives the grabber tint, the VoiceOver
  // labels, and whether the entry card doubles as a "bring it back" target.
  const [padStowed, setPadStowed] = useState(false);

  const keypadStyle = useAnimatedStyle(() => {
    if (padHeight <= 0) return {}; // pre-measurement: lay out naturally
    const byKeyboard = Math.min(1, keyboard.height.value / padHeight);
    const shut = Math.max(byKeyboard, stow.value);
    return { height: padHeight * (1 - shut), opacity: 1 - shut };
  });
  // The keypad carried the home-indicator clearance in its own padding, so once
  // it's stowed the spacer has to take that over as well as standing in for the
  // keyboard.
  const stowedRest = insets.bottom + 8;
  const keyboardSpacer = useAnimatedStyle(() => ({
    height: Math.max(keyboard.height.value, stow.value * stowedRest),
  }));

  // Called on the JS thread whenever `stow` settles somewhere new. Toggling a
  // panel is a toggle, so it takes the selection tick in both directions.
  const syncPad = useCallback((stowed: boolean) => {
    setPadStowed(stowed);
    Haptic.select();
  }, []);

  // `silent` is for callers that already played their own haptic — the keypad
  // returning is a side effect of their action, not a second event to feel.
  function setPad(next: 0 | 1, silent = false) {
    stow.value = withTiming(next, PAD_SETTLE);
    if (silent) setPadStowed(next === 1);
    else syncPad(next === 1);
  }

  // Anything that needs digits brings the keypad back rather than leaving the
  // user to hunt for the grabber.
  function showPad(silent = false) {
    if (padStowed) setPad(0, silent);
  }

  // Dragging the grabber down grows the list: the keypad shrinks, and because
  // the list is the only flexible child, everything between it and the keypad
  // travels with the finger. Horizontal slop fails the gesture so a stray sideways
  // drag doesn't nudge the pad, and the 8pt activation offset leaves the total's
  // long-press-to-copy intact.
  const padDrag = useMemo(
    () =>
      Gesture.Pan()
        .activeOffsetY([-8, 8])
        .failOffsetX([-24, 24])
        .onBegin(() => {
          stowStart.value = stow.value;
        })
        .onUpdate((e) => {
          if (padHeight <= 0) return;
          const v = stowStart.value + e.translationY / padHeight;
          stow.value = v < 0 ? 0 : v > 1 ? 1 : v;
        })
        .onEnd((e) => {
          if (padHeight <= 0) return;
          const next =
            Math.abs(e.velocityY) > PAD_FLING
              ? e.velocityY > 0
                ? 1
                : 0
              : stow.value > 0.5
                ? 1
                : 0;
          stow.value = withTiming(next, PAD_SETTLE);
          // Only when it actually landed somewhere else — a drag that snaps back
          // shouldn't fire a haptic.
          if (next !== stowStart.value) runOnJS(syncPad)(next === 1);
        }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [padHeight, syncPad],
  );

  const preview = Calc.evaluate(draft);
  const showRes = preview != null && Calc.hasOperator(draft);

  function clearDraft() {
    setDraft('');
    setNote('');
    setNoteOpen(false);
    setEditingId(null);
  }

  function press(k: Key) {
    if (k === 'AC') return clearDraft();
    if (k === '⌫') return setDraft((d) => d.slice(0, -1));
    if (k === '✎') return setNoteOpen((o) => !o);
    if (k === '↵') return commit();
    if (k === '%') return setDraft((d) => (/\d$/.test(d) ? d + '%' : d));
    if ('+−×÷'.indexOf(k) >= 0) {
      return setDraft((d) => {
        if (d === '') return k === '−' ? '−' : '';
        if (/[+\-−×÷*/]$/.test(d)) return d.slice(0, -1) + k;
        return d + k;
      });
    }
    if (k === '.') {
      return setDraft((d) => {
        const seg = d.split(/[+\-−×÷*/]/).pop() ?? '';
        if (seg.indexOf('.') >= 0) return d;
        return d === '' ? '0.' : d + '.';
      });
    }
    setDraft((d) => d + k);
  }

  function commit() {
    const val = Calc.evaluate(draft);
    if (draft === '' || val == null) {
      Haptic.error();
      setFlash(true);
      setTimeout(() => setFlash(false), 320);
      return;
    }
    const e: Entry = {
      id: editingId || uid(),
      note: note.trim(),
      expr: Calc.hasOperator(draft) ? draft : '',
      value: val,
    };
    setEntries((list) => (editingId ? list.map((x) => (x.id === editingId ? e : x)) : [...list, e]));
    // Edits happen on a row that's already on screen (the user just tapped
    // it) — only a brand-new entry needs the scroll + flash.
    if (!editingId) setJustAddedId(e.id);
    Haptic.success();
    clearDraft();
  }

  // Selection tick covers both entry points: tapping the row and the native
  // context menu's Edit.
  function editRow(row: Entry) {
    Haptic.select();
    setDraft(row.expr || String(row.value));
    setNote(row.note || '');
    setEditingId(row.id);
    setNoteOpen(false);
    showPad(true); // the selection tick above already covered this
  }

  function deleteRow(id: string) {
    Haptic.impact();
    setEntries((l) => l.filter((x) => x.id !== id));
    if (editingId === id) clearDraft();
  }

  // Long-press the running total → copy the plain number to the clipboard so it
  // pastes cleanly into spreadsheets and other apps.
  async function copyTotal() {
    await Clipboard.setStringAsync(total.toFixed(2));
    Haptic.select();
    setCopied(true);
    setTimeout(() => setCopied(false), 1200);
  }

  // ---- referencing another calculation ----
  // The Σ chip in the entry card opens a native menu of saved calculations;
  // picking one drops its total into the draft. newTab() always snapshots the
  // tab being left, so "the calculation I just finished" is reliably the top
  // item. Values are pasted as plain numbers (a snapshot, not a live link) —
  // the note is prefilled with the source's name so the row keeps saying where
  // the figure came from. Capped so the menu stays a menu, not an archive.
  const refTabs = useMemo(
    () => tabs.filter((tb) => tb.id !== activeId && (tb.entries?.length ?? 0) > 0).slice(0, 12),
    [tabs, activeId],
  );

  const tabTotal = (tb: Tab) => (tb.entries ?? []).reduce((a, e) => a + (e.value || 0), 0);

  function insertRef(tb: Tab) {
    const val = Math.round(tabTotal(tb) * 100) / 100;
    const num = String(Math.abs(val));
    const neg = val < 0;
    Haptic.select();
    setDraft((d) => {
      if (d === '') return (neg ? '−' : '') + num;
      // after + or −, fold a negative total into the sign: "5+" & −3.5 → "5−3.5"
      if (/[+−]$/.test(d)) return neg ? d.slice(0, -1) + (d.endsWith('+') ? '−' : '+') + num : d + num;
      // after × or ÷ the flat engine has no way to say "(−n)" — use the
      // magnitude rather than silently mangling the expression
      if (/[×÷*/]$/.test(d)) return d + num;
      // mid-number: a running tab adds things, so joining with + is the
      // predictable default (and the preview shows exactly what happened)
      return d + (neg ? '−' : '+') + num;
    });
    if (!note) setNote(tb.name);
    showPad(true); // the selection tick above already covered this
  }

  // The entry card's contents — shared by the glass and opaque surfaces.
  const entryBody = (
    <>
      <View style={styles.entryTop}>
        <View style={styles.entryTopLhs}>
          {noteOpen ? (
            <TextInput
              ref={noteInputRef}
              style={[styles.noteInput, { color: t.ink }]}
              value={note}
              placeholder="add a note…"
              placeholderTextColor={t.ink3}
              onChangeText={setNote}
              onSubmitEditing={() => setNoteOpen(false)}
              returnKeyType="done"
              clearButtonMode="while-editing"
              maxFontSizeMultiplier={1.4}
            />
          ) : note ? (
            <Pressable style={[styles.chip, { backgroundColor: t.accent2 }]} onPress={() => setNoteOpen(true)}>
              <Text style={[styles.chipText, { color: t.accentInk }]} numberOfLines={1}>
                {note}
              </Text>
            </Pressable>
          ) : (
            <Pressable style={[styles.chipGhost, { backgroundColor: t.accent2 }]} onPress={() => setNoteOpen(true)}>
              <Text style={[styles.chipText, { color: t.accentInk }]}>+ note</Text>
            </Pressable>
          )}
          {/* Σ — reference another calculation: a native menu of saved tabs
              with their totals; picking one pastes the total into the draft.
              Hidden while the note field is typing (the row is the field's). */}
          {!noteOpen && refTabs.length > 0 && (
            <View style={[styles.refChip, { backgroundColor: t.accent2 }]}>
              <Host style={styles.refHost}>
                <Menu
                  label={
                    <Image
                      systemName="sum"
                      size={13}
                      color={t.accentInk}
                      modifiers={[
                        frame({ width: 34, height: 26 }),
                        contentShape(shapes.rectangle()),
                        accessibilityLabel('Use a saved total'),
                      ]}
                    />
                  }>
                  {refTabs.map((tb) => (
                    <Button
                      key={tb.id}
                      label={`${tb.name} — ${Calc.fmt(tabTotal(tb))}`}
                      onPress={() => insertRef(tb)}
                    />
                  ))}
                </Menu>
              </Host>
            </View>
          )}
        </View>
        {showRes && <Text style={[styles.resTxt, { color: t.accent }]}>= {Calc.fmt(preview)}</Text>}
      </View>
      {/* capped at 1.15 so the glyphs stay inside the card's fixed 44pt line box */}
      <Text style={[styles.draftBig, { color: draft ? t.ink : t.ink3 }]} numberOfLines={1} maxFontSizeMultiplier={1.15}>
        {draft || '0'}
      </Text>
    </>
  );

  return (
    <View style={[styles.root, { paddingTop: insets.top }]}>
      <ScreenBackground theme={t} mode={themeMode} />
      <StatusBar style={themeMode === 'dark' ? 'light' : 'dark'} />

      {/* header: tab title (opens the Save sheet) · ⋯ overflow menu */}
      <View style={styles.head}>
        <View style={styles.headLhs}>
          <Pressable onPress={() => setSaveOpen(true)} hitSlop={6}>
            <Text
              style={[styles.sesName, { color: tabName ? t.ink : t.ink3 }, !tabName && styles.sesNameEmpty]}
              numberOfLines={1}>
              {tabName || 'Tap to name and save'}
            </Text>
          </Pressable>
        </View>

        {/* native SwiftUI menu — trigger + dropdown rendered by iOS itself.
            New calculation sits up top, then the heavier destinations. */}
        <View style={styles.menuWrap}>
          {/* fixed 44pt host, not matchContents: SwiftUI hit-tests the Menu label
              and RN clips touches to the host bounds, so a glyph-sized host left
              a ~25pt target that swallowed taps. frame + contentShape give the
              label the full 44pt square HIG asks for. */}
          <Host style={styles.menuHost}>
            <Menu
              label={
                <Image
                  systemName="ellipsis"
                  size={22}
                  color={t.ink2}
                  modifiers={[
                    frame({ width: MENU_HIT, height: MENU_HIT }),
                    contentShape(shapes.rectangle()),
                    accessibilityLabel('More options'),
                  ]}
                />
              }
              modifiers={[tint('#FFFFFF')]}>
              {/* medium impact: clears the working tab, a significant change */}
              <Button
                label="New calculation"
                systemImage="plus"
                onPress={() => {
                  Haptic.impact();
                  newTab();
                  showPad(true); // a fresh tab is there to be typed into
                }}
              />
              <Divider />
              <Button
                label={tabs.length > 0 ? `Saved calculations (${tabs.length})` : 'Saved calculations'}
                systemImage="tray.full"
                onPress={() => router.push('/saved')}
              />
              <Button label="Settings" systemImage="gearshape" onPress={() => router.push('/settings')} />
            </Menu>
          </Host>
          {tabs.length > 0 && (
            <View style={[styles.countBadge, { backgroundColor: t.accent }]} pointerEvents="none">
              {/* the one deliberate Dynamic Type opt-out: a 15pt badge disc has
                  nowhere to grow, and the count is repeated in the menu label */}
              <Text style={styles.countBadgeText} allowFontScaling={false}>
                {tabs.length}
              </Text>
            </View>
          )}
        </View>
      </View>

      {/* the running list — a native SwiftUI List so each row gets real
          swipe-to-delete and a long-press context menu (see SwipeRow). */}
      {entries.length === 0 ? (
        <View style={styles.empty}>
          <Text style={[styles.emptyTitle, { color: t.ink2 }]}>Nothing tallied yet.</Text>
          {/* was "hit ↵" — Geist has no glyph for U+21B5, so it rendered in a
              substituted font and VoiceOver read it as nothing useful */}
          <Text style={[styles.emptyHint, { color: t.ink3 }]}>Tap a number, name it, then hit return</Text>
        </View>
      ) : (
        // the wrapper View exists to give ListScroll a react tag to search
        // under — @expo/ui's Host doesn't expose one (collapsable=false so RN
        // can't flatten it away)
        <View ref={listWrapRef} style={styles.list} collapsable={false}>
          <Host style={styles.listHost}>
            <List
              modifiers={[
                listStyle('plain'),
                scrollContentBackground('hidden'),
                listRowSpacing(0),
                listSectionSpacing(0),
              ]}>
              <Section>
                {entries.map((e, i) => (
                  <SwipeRow
                    key={e.id}
                    entry={e}
                    selected={e.id === editingId}
                    showExpr={showExpr}
                    last={i === entries.length - 1}
                    justAdded={e.id === justAddedId}
                    theme={t}
                    onEdit={editRow}
                    onDelete={deleteRow}
                  />
                ))}
              </Section>
            </List>
          </Host>
        </View>
      )}

      {/* The seam between reviewing (the list) and entering (card + keypad), and
          the handle for the keypad: drag anywhere on this block, or tap the
          grabber. It renders even with the total switched off, so there's always
          somewhere to grab. */}
      <GestureDetector gesture={padDrag}>
        <View>
          <Pressable
            style={styles.grabHit}
            onPress={() => setPad(padStowed ? 0 : 1)}
            hitSlop={{ top: 8, bottom: 8 }}
            accessibilityRole="button"
            accessibilityLabel={padStowed ? 'Show keypad' : 'Hide keypad'}
            accessibilityHint="Hiding the keypad gives the list of amounts the rest of the screen">
            {/* accent while stowed: the app's "active" colour everywhere else,
                so a tinted grabber reads as "something is put away here" */}
            <View style={[styles.grab, { backgroundColor: padStowed ? t.accent : t.ink3 }]} />
          </Pressable>

          {/* live total — long-press to copy */}
          {showTotal && (
            <Pressable
              onLongPress={copyTotal}
              delayLongPress={350}
              style={({ pressed }) => [
                styles.total,
                { borderTopColor: t.line },
                pressed && styles.totalPressed,
              ]}>
              <Animated.Text
                key={copied ? 'copied' : 'total'}
                entering={FadeIn.duration(200)}
                style={[styles.tLab, { color: copied ? t.accent : t.ink2 }]}>
                {/* the ✓ that used to trail this is gone: it's the last stray text
                    glyph, and the accent colour plus the fade already read as
                    confirmation without leaning on a substituted font */}
                {copied ? 'Copied' : 'Total'}
              </Animated.Text>
              <AnimatedTotal value={total} color={t.ink} />
            </Pressable>
          )}
        </View>
      </GestureDetector>

      {/* No edit banner: the highlighted row and the accent border on the entry
          card already say what's being edited. Delete lives on the row itself
          (swipe / context menu) and AC backs out of the edit. */}

      {/* in-progress entry — native Liquid Glass on iOS 26+, opaque card
          otherwise. The border turns accent on an invalid commit (flash) and
          while a row is being edited, per the design.
          While the keypad is stowed the card is also the way back to it: the
          obvious place to tap when you want to type. The wrapper stays mounted
          either way so the glass surface isn't torn down and rebuilt on toggle;
          showPad no-ops when the keypad is already up, and the note chip and
          field inside still win the touch. */}
      <Pressable
        onPress={() => showPad()}
        accessible={padStowed}
        accessibilityRole={padStowed ? 'button' : undefined}
        accessibilityLabel={padStowed ? 'Show keypad' : undefined}>
        {LIQUID ? (
          <GlassView
            glassEffectStyle="regular"
            colorScheme={themeMode}
            style={[styles.entry, styles.entryGlass, { borderColor: flash || editingId ? t.accent : t.line }]}>
            {entryBody}
          </GlassView>
        ) : (
          <View
            style={[styles.entry, { backgroundColor: t.card, borderColor: flash || editingId ? t.accent : t.line }]}>
            {entryBody}
          </View>
        )}
      </Pressable>

      {/* tag the current tab — toggles tags live before the tab is even saved */}
      {entries.length > 0 && (
        <View style={styles.tagWrap}>
          <Text style={[styles.tagLead, { color: t.ink3 }]} maxFontSizeMultiplier={1.6}>
            TAGS ON THIS TAB
          </Text>
          <TagToggleGlass
            theme={t}
            mode={themeMode}
            catalog={catalog}
            value={tags}
            onChange={setTags}
            onCreate={addCatalogTag}
          />
        </View>
      )}

      {/* measured once, then driven to zero height as the keyboard rises */}
      <Animated.View
        style={[styles.keypadWrap, keypadStyle]}
        onLayout={(e) => {
          const h = e.nativeEvent.layout.height;
          if (h > 0 && padHeight === 0) setPadHeight(h);
        }}>
        <Keypad theme={t} themeMode={themeMode} onPress={press} bottomInset={insets.bottom} />
      </Animated.View>
      <Animated.View style={keyboardSpacer} pointerEvents="none" />

      <SaveSheet visible={saveOpen} onClose={() => setSaveOpen(false)} />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  head: {
    paddingHorizontal: 20,
    paddingTop: 2,
    paddingBottom: 14,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  headLhs: { flex: 1, minWidth: 0 },
  sesName: { fontFamily: TallyFonts.serif, fontSize: 19, lineHeight: 22, letterSpacing: -0.3 },
  sesNameEmpty: { fontStyle: 'italic' },

  // The 44pt box is wider than the glyph, so it hangs into head's right padding
  // by MENU_BLEED — that keeps the dots optically on the 20pt content margin and
  // the slop stays inside head's bounds, where RN still routes touches to it.
  menuWrap: { position: 'relative', width: MENU_HIT, height: MENU_HIT, marginRight: -MENU_BLEED },
  menuHost: { width: MENU_HIT, height: MENU_HIT },
  countBadge: {
    // tuned to hug the 22pt glyph sitting centred inside the 44pt target
    position: 'absolute',
    top: 4,
    right: 3,
    minWidth: 15,
    height: 15,
    paddingHorizontal: 3,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  countBadgeText: { color: '#fff', fontFamily: TallyFonts.monoSemi, fontSize: 9, lineHeight: 11 },

  list: { flex: 1, paddingHorizontal: 16 },
  listHost: { flex: 1 },

  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 10, padding: 20 },
  emptyTitle: { fontFamily: TallyFonts.serif, fontSize: 20, lineHeight: 22, textAlign: 'center', maxWidth: 180 },
  emptyHint: { fontFamily: TallyFonts.sans, fontSize: 13, lineHeight: 19 },

  // Full-width strip so the keypad handle is easy to hit; 30pt plus 8pt of
  // hitSlop each way clears the 44pt HIG target on its short axis.
  grabHit: { height: 30, alignItems: 'center', justifyContent: 'center' },
  grab: { width: 36, height: 5, borderRadius: 2.5, opacity: 0.5 },

  total: {
    marginHorizontal: 20,
    marginTop: 2,
    marginBottom: 10,
    paddingTop: 10,
    borderTopWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    gap: 10,
  },
  totalPressed: { opacity: 0.6 },
  tLab: { fontFamily: TallyFonts.sansMedium, fontSize: 13 },
  tBig: { fontFamily: TallyFonts.monoSemi, fontSize: 20, fontVariant: ['tabular-nums'], letterSpacing: -0.2 },


  entry: {
    marginHorizontal: 16,
    marginBottom: 10,
    paddingTop: 12,
    paddingBottom: 14,
    paddingHorizontal: 16,
    borderWidth: 1,
    borderRadius: 20,
    gap: 6,
    // the design's lifted "glass" elevation (shadow-glass): a deep, soft drop
    ...Elevation.glass,
  },
  // Liquid Glass surface: drop the opaque fill and clip the material to the radius.
  entryGlass: { backgroundColor: 'transparent', overflow: 'hidden' },
  entryTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 10, minHeight: 24 },
  entryTopLhs: { flex: 1, minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 6 },
  // the Σ "use a saved total" chip — sized to match the note chip's height;
  // the SwiftUI Menu inside owns the tap
  refChip: { borderRadius: 9, overflow: 'hidden' },
  refHost: { width: 34, height: 26 },
  chip: { paddingVertical: 5, paddingHorizontal: 10, borderRadius: 9, maxWidth: 120 },
  chipGhost: { paddingVertical: 5, paddingHorizontal: 10, borderRadius: 9 },
  chipText: { fontFamily: TallyFonts.sansSemi, fontSize: 12.5 },
  noteInput: { flex: 1, fontFamily: TallyFonts.sansSemi, fontSize: 14, padding: 0 },
  resTxt: { fontFamily: TallyFonts.monoMedium, fontSize: 13 },
  draftBig: {
    fontFamily: TallyFonts.monoSemi,
    fontSize: 36,
    lineHeight: 44,
    textAlign: 'right',
    fontVariant: ['tabular-nums'],
    letterSpacing: -0.8,
  },

  // clips the keypad as it collapses behind the rising keyboard
  keypadWrap: { overflow: 'hidden' },

  tagWrap: { paddingBottom: 12, gap: 8 },
  tagLead: { fontFamily: TallyFonts.mono, fontSize: 9.5, letterSpacing: 1.7, paddingHorizontal: 16 },
});
