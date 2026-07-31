// index.tsx — Tally, the running-tab calculator (2026 refresh). One screen:
// a nameable tab, a labelled list of amounts, a live total, the in-progress
// entry, optional tag chips, and the keypad. The title's pull-down menu renames
// the tab and opens the Saved archive and Settings.
//
// The keypad is ~360pt — around 40% of the screen — so it can be stowed to give
// the list that space back: drag the grabber above the total down, or tap it.
// See "keypad avoidance" below; stowing and the system keyboard share one
// collapse path so they can't fight each other.
import { Button, Divider, Host, Image, List, Menu, Section } from '@expo/ui/swift-ui';
import {
  accessibilityHint,
  accessibilityLabel,
  buttonStyle,
  contentShape,
  font,
  foregroundColor,
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
import { Stack, useRouter } from 'expo-router';
import { useHeaderHeight } from 'expo-router/react-navigation';
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

import { ExprView } from '@/components/tally/expr-view';
import { Keypad, type Key } from '@/components/tally/keypad';
import { SaveSheet } from '@/components/tally/save-sheet';
import { ScreenBackground } from '@/components/tally/screen-bg';
import { SwipeRow } from '@/components/tally/swipe-row';
import { TallyFonts } from '@/constants/tally-theme';
import { Elevation } from '@/constants/tokens';
import * as Calc from '@/lib/calc-engine';
import * as Haptic from '@/lib/haptics';
import { uid, useTally, type Entry } from '@/lib/tally-store';
import { scrollListToEnd } from '../../modules/list-scroll';

// iOS 26+ renders the entry card as native Liquid Glass; older OS keeps the
// opaque card. Resolved once at module load.
const LIQUID = isLiquidGlassAvailable();

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
  // The nav bar floats over the screen (headerTransparent, so the accent bloom
  // keeps running behind it), so the body is pushed down by hand — the same
  // arrangement the Saved screen uses.
  const headerHeight = useHeaderHeight();
  const {
    entries,
    setEntries,
    total,
    theme: t,
    themeMode,
    showExpr,
    showTotal,
    tabs,
    tabName,
    newTab,
  } = useTally();

  const [draft, setDraft] = useState('');
  const [note, setNote] = useState('');
  const [noteOpen, setNoteOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [flash, setFlash] = useState(false);
  const [copied, setCopied] = useState(false);
  const [saveOpen, setSaveOpen] = useState(false);

  // ---- multi-select ----
  // "What do these three come to?" — a question the running total can't answer.
  // Select mode turns every row into a checkbox and swaps the total for the
  // subtotal of what's ticked. It's a read-only lens: nothing is committed, and
  // Done puts the screen back exactly as it was.
  const [selectMode, setSelectMode] = useState(false);
  const [picked, setPicked] = useState<Set<string>>(() => new Set());

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

  // Selecting is reading, not typing, so the keypad stows for the duration and
  // the list gets its ~360pt. Whatever the keypad was doing before is restored
  // on Done — someone who had already stowed it doesn't want it back.
  const padBeforeSelect = useRef(false);

  // `deferMs` is for the one caller that turns the mode on from inside a row's
  // context menu: the rows restructure when it flips (no menu while selecting),
  // and doing that while iOS is still animating the menu away strands the
  // dismissing preview over the list. Waiting out the dismissal is the fix; the
  // haptic still fires on the tap, so the delay reads as the menu closing.
  const MENU_DISMISS = 380;

  function startSelect(seed?: Entry, deferMs = 0) {
    Haptic.select();
    const enter = () => {
      clearDraft();
      setPicked(new Set(seed ? [seed.id] : []));
      setSelectMode(true);
      padBeforeSelect.current = padStowed;
      if (!padStowed) setPad(1, true); // the tick above already covered this
    };
    if (deferMs > 0) setTimeout(enter, deferMs);
    else enter();
  }

  function endSelect() {
    Haptic.select();
    setSelectMode(false);
    setPicked(new Set());
    if (!padBeforeSelect.current) setPad(0, true);
  }

  function togglePick(row: Entry) {
    Haptic.select();
    setPicked((prev) => {
      const next = new Set(prev);
      if (!next.delete(row.id)) next.add(row.id);
      return next;
    });
  }

  const pickedSum = useMemo(
    () => entries.reduce((a, x) => (picked.has(x.id) ? a + x.value : a), 0),
    [entries, picked],
  );

  // Rows can be deleted from under a selection (via Saved, or an edit that
  // removes one), so the tick count is always derived from live entries.
  const pickedCount = useMemo(() => entries.reduce((n, x) => n + (picked.has(x.id) ? 1 : 0), 0), [entries, picked]);
  const allPicked = entries.length > 0 && pickedCount === entries.length;

  function toggleAll() {
    Haptic.select();
    setPicked(allPicked ? new Set() : new Set(entries.map((x) => x.id)));
  }

  // Dragging the grabber down grows the list: the keypad shrinks, and because
  // the list is the only flexible child, everything between it and the keypad
  // travels with the finger. Horizontal slop fails the gesture so a stray sideways
  // drag doesn't nudge the pad, and the 8pt activation offset leaves the total's
  // long-press-to-copy intact.
  const padDrag = useMemo(
    () =>
      Gesture.Pan()
        // nothing to reveal while selecting — the keypad is stowed on purpose
        .enabled(!selectMode)
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
    [padHeight, syncPad, selectMode],
  );

  // Resolver for the draft's reference tokens: entry ids look up the current
  // value; `sum` is the running total of the lines the draft can see — all of
  // them for a new line, only the ones above when editing (matching the
  // forward-pass evaluation order in the store).
  const editIndex = editingId ? entries.findIndex((x) => x.id === editingId) : -1;
  const resolveRef = (id: string): number | null => {
    if (id === 'sum') {
      const upto = editIndex >= 0 ? editIndex : entries.length;
      return entries.slice(0, upto).reduce((a, x) => a + x.value, 0);
    }
    const src = entries.find((x) => x.id === id);
    return src ? src.value : null;
  };

  const draftRefs = Calc.refsIn(draft);
  const preview = Calc.evaluate(draft, resolveRef);
  const showRes = preview != null && (Calc.hasOperator(draft) || draftRefs.length > 0);

  function clearDraft() {
    setDraft('');
    setNote('');
    setNoteOpen(false);
    setEditingId(null);
  }

  function press(k: Key) {
    if (k === 'AC') return clearDraft();
    // backspace removes a whole reference pill, never half a token
    if (k === '⌫') return setDraft((d) => d.replace(/\{(?:e\d+|sum)\}$|.$/, ''));
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
        if (seg.endsWith('}')) return d; // a pill is a finished number
        if (seg.indexOf('.') >= 0) return d;
        return d === '' ? '0.' : d + '.';
      });
    }
    // a digit straight after a pill starts a new term — join with + (the
    // running-tab default), same rule the Σ insert uses in the other direction
    setDraft((d) => (/\}$/.test(d) ? d + '+' + k : d + k));
  }

  function commit() {
    const val = Calc.evaluate(draft, resolveRef);
    if (draft === '' || val == null) {
      Haptic.error();
      setFlash(true);
      setTimeout(() => setFlash(false), 320);
      return;
    }
    const e: Entry = {
      id: editingId || uid(),
      note: note.trim(),
      // references must survive in expr even without an operator — a bare
      // ⟨Rent⟩ line is a live mirror, not a copy
      expr: Calc.hasOperator(draft) || draftRefs.length > 0 ? draft : '',
      value: val,
      // an edit keeps the line's sticky number — only new lines get a fresh one
      num: editingId ? entries.find((x) => x.id === editingId)?.num : undefined,
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

  // Long-press the running total — or a selection's subtotal — → copy the plain
  // number to the clipboard so it pastes cleanly into spreadsheets and other apps.
  async function copyTotal(value: number) {
    await Clipboard.setStringAsync(value.toFixed(2));
    Haptic.select();
    setCopied(true);
    setTimeout(() => setCopied(false), 1200);
  }

  // ---- referencing an earlier line ----
  // The Σ chip in the entry card opens a native menu of this tab's committed
  // lines, newest first, plus "Total so far". Picking one drops a *reference
  // token* into the draft — a live link rendered as a named pill, so the row
  // recomputes whenever the referenced line changes (see tally-store). A line
  // may only reference lines above it: composing a new line sees everything,
  // editing sees just the lines above the one being edited. That one rule is
  // also what makes reference cycles impossible. Capped so the menu stays a
  // menu, not an archive.
  const refVisible = editIndex >= 0 ? entries.slice(0, editIndex) : entries;
  const refEntries = refVisible.slice(-12).reverse();

  /** Display name for a reference id — a note, '#4', or the subtotal. */
  const nameFor = useCallback(
    (id: string): string => {
      if (id === 'sum') return 'Σ total';
      const src = entries.find((x) => x.id === id);
      if (!src) return '#?';
      if (!src.note) return `#${src.num ?? '?'}`;
      return src.note.length > 16 ? src.note.slice(0, 15) + '…' : src.note;
    },
    [entries],
  );

  /** How a line reads in the Σ menu: its name, then its current value. */
  const refLabel = (e: Entry) => {
    const name = e.note || `#${e.num ?? '?'}`;
    return `${name} — ${Calc.fmt(e.value)}`;
  };

  function insertRef(id: string, sourceNote?: string) {
    const tok = `{${id}}`;
    Haptic.select();
    setDraft((d) => {
      if (d === '') return tok;
      if (/[+−×÷*/]$/.test(d)) return d + tok;
      // mid-number (or right after another pill): a running tab adds things,
      // so joining with + is the predictable default — and the preview shows
      // exactly what happened
      return d + '+' + tok;
    });
    if (!note && sourceNote) setNote(sourceNote);
    showPad(true); // the selection tick above already covered this
  }

  // ---- navigation bar items ----
  // Each one is a SwiftUI control inside a Host, so the press states, the tint,
  // Dynamic Type and the VoiceOver traits are the system's rather than ours.

  // The title, doubling as this calculation's pull-down menu. Three groups:
  // what you can do to the calculation, starting a fresh one, and where else to
  // go — enough items to be worth opening (HIG "Pull-down buttons") without
  // burying the screen's real work, which is the keypad below.
  const renderTitleMenu = () => (
    // The nav bar measures a custom title view once, and a Host that starts at
    // 0x0 while SwiftUI lays out never gets measured again — hence the fixed
    // box rather than matchContents.
    <Host style={styles.titleHost}>
      {/* A plain string label, not a composed HStack of text + chevron: a
          ReactNode label goes through @expo/ui's Slot, and a slotted label
          silently renders nothing inside the nav bar's title view. So the
          chevron is a character, drawn in SF by SwiftUI (not in Geist, which
          has no glyph for it) — and hidden from VoiceOver by the label below. */}
      <Menu
        label={`${tabName || 'New calculation'}  ⌄`}
        modifiers={[
          font({ family: TallyFonts.sansSemi, textStyle: 'headline' }),
          foregroundColor(t.ink),
          tint(t.accent),
          accessibilityLabel(
            tabName ? `${tabName}, calculation options` : 'Unnamed calculation, options',
          ),
        ]}>
        <Button label="Rename & tags…" systemImage="pencil" onPress={() => setSaveOpen(true)} />
        <Button label="Copy total" systemImage="doc.on.doc" onPress={() => copyTotal(total)} />
        <Divider />
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
  );

  const renderSelect = () => (
    <Host matchContents>
      <Button
        label="Select"
        onPress={() => startSelect()}
        modifiers={[
          tint(t.accent),
          accessibilityHint('Tick several lines to see what they come to together'),
        ]}
      />
    </Host>
  );

  const renderSelectAll = () => (
    <Host matchContents>
      <Button label={allPicked ? 'Deselect All' : 'Select All'} onPress={toggleAll} modifiers={[tint(t.accent)]} />
    </Host>
  );

  // The one primary action on screen while selecting, so it takes the prominent
  // style HIG reserves for exactly that — glass where the OS has it.
  const renderDone = () => (
    <Host matchContents>
      <Button
        label="Done"
        onPress={endSelect}
        modifiers={[buttonStyle(LIQUID ? 'glassProminent' : 'borderedProminent'), tint(t.accent)]}
      />
    </Host>
  );

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
          {/* Σ — reference an earlier line: a native menu of this tab's rows,
              newest first, plus the running subtotal. Picking one drops a live
              reference pill into the draft.
              Hidden while the note field is typing (the row is the field's). */}
          {!noteOpen && refEntries.length > 0 && (
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
                        accessibilityLabel('Reference an earlier line'),
                      ]}
                    />
                  }>
                  <Button
                    label={`Total so far — ${Calc.fmt(resolveRef('sum'))}`}
                    onPress={() => insertRef('sum')}
                  />
                  <Divider />
                  {refEntries.map((e) => (
                    <Button key={e.id} label={refLabel(e)} onPress={() => insertRef(e.id, e.note)} />
                  ))}
                </Menu>
              </Host>
            </View>
          )}
        </View>
        {showRes && <Text style={[styles.resTxt, { color: t.accent }]}>= {Calc.fmt(preview)}</Text>}
      </View>
      {/* capped at 1.15 so the glyphs stay inside the card's fixed 44pt line box.
          A draft holding reference tokens renders as text + named pills instead. */}
      {draftRefs.length > 0 ? (
        <ExprView expr={draft} nameFor={nameFor} theme={t} variant="draft" />
      ) : (
        <Text style={[styles.draftBig, { color: draft ? t.ink : t.ink3 }]} numberOfLines={1} maxFontSizeMultiplier={1.15}>
          {draft || '0'}
        </Text>
      )}
    </>
  );

  return (
    <View style={[styles.root, { paddingTop: headerHeight }]}>
      <ScreenBackground theme={t} mode={themeMode} />
      <StatusBar style={themeMode === 'dark' ? 'light' : 'dark'} />

      {/* A real UINavigationBar, so every control in it is a system control
          (HIG "Toolbars"). Transparent, because the screen's accent bloom has to
          keep running behind it; inline rather than large, for the same reason
          the Saved screen gives — only an RN ScrollView can drive the large
          title's collapse, and the body here is a SwiftUI List.

          At rest the title doubles as the pull-down "document menu" HIG puts
          next to a title: everything that acts on this calculation, then the two
          destinations. Select sits alone on the trailing edge — one text button,
          so it can't read as a label attached to a neighbouring symbol.

          While selecting, the bar belongs to the selection, the way Photos does
          it: Select All leading, and Done — the single primary action — trailing
          in the prominent style HIG asks for. */}
      <Stack.Screen
        options={{
          headerShown: true,
          headerTransparent: true,
          headerShadowVisible: false,
          headerTintColor: t.accent,
          title: tabName || 'New calculation',
          headerTitleStyle: { color: t.ink, fontFamily: TallyFonts.sansSemi },
          // while selecting, the bar is the selection's — the title is just a
          // label, and Done is the only way back out
          headerTitle: selectMode ? undefined : renderTitleMenu,
          headerLeft: selectMode ? renderSelectAll : undefined,
          headerRight: selectMode
            ? renderDone
            : entries.length > 1
              ? renderSelect
              : undefined,
        }}
      />

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
                    nameFor={nameFor}
                    theme={t}
                    selectMode={selectMode}
                    picked={picked.has(e.id)}
                    canReference={editIndex < 0 || i < editIndex}
                    onEdit={editRow}
                    onDelete={deleteRow}
                    onSelect={(row) => startSelect(row, MENU_DISMISS)}
                    onReference={(row) => insertRef(row.id, row.note)}
                    onToggle={togglePick}
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
            disabled={selectMode}
            onPress={() => setPad(padStowed ? 0 : 1)}
            hitSlop={{ top: 13, bottom: 13 }}
            accessibilityRole="button"
            accessibilityLabel={padStowed ? 'Show keypad' : 'Hide keypad'}
            accessibilityHint="Hiding the keypad gives the list of amounts the rest of the screen">
            {/* accent while stowed: the app's "active" colour everywhere else,
                so a tinted grabber reads as "something is put away here" */}
            <View style={[styles.grab, { backgroundColor: padStowed ? t.accent : t.ink3 }]} />
          </Pressable>

          {/* live total — long-press to copy. While selecting, the same slot
              carries the subtotal of the ticked lines: the answer lands where
              the eye already goes for a total, and it counts up as rows are
              ticked. The subtotal shows even with the total switched off —
              it's the whole point of the mode. */}
          {selectMode ? (
            // keyed apart from the total below so the count-up starts from the
            // subtotal rather than tweening down from the grand total
            <Pressable
              key="subtotal"
              onLongPress={() => copyTotal(pickedSum)}
              delayLongPress={350}
              style={({ pressed }) => [styles.total, { borderTopColor: t.line }, pressed && styles.totalPressed]}>
              <Animated.Text
                key={copied ? 'copied' : 'picked'}
                entering={FadeIn.duration(200)}
                style={[styles.tLab, { color: copied ? t.accent : t.ink2 }]}>
                {copied
                  ? 'Copied'
                  : pickedCount === 0
                    ? 'Tap lines to add them up'
                    : `${pickedCount} of ${entries.length} selected`}
              </Animated.Text>
              <AnimatedTotal value={pickedSum} color={pickedCount > 0 ? t.accent : t.ink3} />
            </Pressable>
          ) : (
            showTotal && (
              <Pressable
                key="total"
                onLongPress={() => copyTotal(total)}
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
            )
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
        // there's nothing to type into while selecting; the card takes itself
        // out of the layout (not out of the tree — the glass survives)
        style={selectMode ? styles.gone : undefined}
        disabled={selectMode}
        accessible={padStowed && !selectMode}
        accessibilityRole={padStowed && !selectMode ? 'button' : undefined}
        accessibilityLabel={padStowed && !selectMode ? 'Show keypad' : undefined}>
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

      {/* No tag strip here any more: tagging is a property of a finished
          calculation, not of the one being typed. It lives on the Saved list —
          long-press a row for the Tags submenu — plus the Save sheet. */}

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
  // out of the layout but still mounted (SwiftUI hosts, glass surfaces)
  gone: { display: 'none' },

  // the nav bar's title pull-down (see renderTitleMenu)
  titleHost: { height: 34, width: 220 },

  // Full-bleed on purpose: the scroll indicator rides the host's trailing edge,
  // so padding here parked it 16pt in from the screen edge. The 16pt content
  // margin lives on the rows instead (listRowInsets in SwipeRow).
  list: { flex: 1 },
  listHost: { flex: 1, backgroundColor: 'transparent' },

  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 10, padding: 20 },
  emptyTitle: { fontFamily: TallyFonts.serif, fontSize: 20, lineHeight: 22, textAlign: 'center', maxWidth: 180 },
  emptyHint: { fontFamily: TallyFonts.sans, fontSize: 13, lineHeight: 19 },

  // Full-width strip so the keypad handle is easy to hit; the strip is drawn
  // small (18pt) to keep the seam tight, and the 13pt hitSlop each way makes
  // up the 44pt HIG target on its short axis.
  grabHit: { height: 18, alignItems: 'center', justifyContent: 'center' },
  grab: { width: 32, height: 4, borderRadius: 2, opacity: 0.5 },

  total: {
    marginHorizontal: 20,
    marginTop: 0,
    marginBottom: 6,
    paddingTop: 6,
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
    marginBottom: 8,
    paddingTop: 10,
    paddingBottom: 12,
    paddingHorizontal: 16,
    borderWidth: 1,
    borderRadius: 20,
    gap: 4,
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
});
