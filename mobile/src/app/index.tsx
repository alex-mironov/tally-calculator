// index.tsx — Tally, the running-tab calculator (2026 refresh). One screen:
// a nameable tab, a labelled list of amounts, a live total, the in-progress
// entry, optional tag chips, and the keypad. The title's pull-down menu renames
// the tab and opens the Saved archive and Settings.
//
// The keypad is ~360pt — around 40% of the screen — so it can be stowed to give
// the list that space back: drag the grabber above the total down, or tap it.
// See "keypad avoidance" below; stowing and the system keyboard share one
// collapse path so they can't fight each other.
import { Button, Divider, Host, Image, Menu } from '@expo/ui/swift-ui';
import { accessibilityLabel, contentShape, frame, shapes } from '@expo/ui/swift-ui/modifiers';
import * as Clipboard from 'expo-clipboard';
import { GlassView, isLiquidGlassAvailable } from 'expo-glass-effect';
import { Stack, useRouter } from 'expo-router';
import { useHeaderHeight } from 'expo-router/react-navigation';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Alert,
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
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { ExprView } from '@/components/tally/expr-view';
import { Keypad, type Key } from '@/components/tally/keypad';
import { SaveSheet } from '@/components/tally/save-sheet';
import { ScreenBackground } from '@/components/tally/screen-bg';
import { GroupedList } from '@/components/tally/grouped-list';
import { SwipeRow } from '@/components/tally/swipe-row';
import { TallyFonts } from '@/constants/tally-theme';
import { Elevation } from '@/constants/tokens';
import * as Calc from '@/lib/calc-engine';
import * as Haptic from '@/lib/haptics';
import { shareCalculation } from '@/lib/share-link';
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
    tags,
    tabEpoch,
    newTab,
    accent,
  } = useTally();

  const [draft, setDraft] = useState('');
  const [note, setNote] = useState('');
  const [noteOpen, setNoteOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [flash, setFlash] = useState(false);
  const [copied, setCopied] = useState(false);
  const [saveOpen, setSaveOpen] = useState(false);

  const noteInputRef = useRef<RNTextInput>(null);
  // iOS hands a focused field one last onChangeText as it goes away — a pending
  // autocorrect / predictive-text commit that lands after the fact. That event
  // was re-filling the note we had *just* cleared, so the note from the line you
  // committed was still sitting on the card when the next one started. The field
  // may only write to `note` while it's genuinely the thing being typed into;
  // clearDraft and editRow shut that window synchronously, ahead of the
  // teardown, so the late event is dropped instead of resurrecting the note.
  const noteLive = useRef(false);

  useEffect(() => {
    noteLive.current = noteOpen;
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
  // Shared values are written through `set()` rather than `.value =` here and
  // in the drag below: Reanimated added the method for the React Compiler,
  // which treats a `.value` assignment after the value has reached a hook
  // (useAnimatedStyle above) as an illegal mutation and skips the screen.
  function setPad(next: 0 | 1, silent = false) {
    stow.set(withTiming(next, PAD_SETTLE));
    if (silent) setPadStowed(next === 1);
    else syncPad(next === 1);
  }

  // Anything that needs digits brings the keypad back rather than leaving the
  // user to hunt for the grabber.
  function showPad(silent = false) {
    if (padStowed) setPad(0, silent);
  }

  // ---- multi-select, in place ----
  // "What do these three come to?" — a question the running total can't answer.
  // It used to open a sheet over the tab, which meant re-reading the same list
  // in a second copy of itself. Now the tab *becomes* the answer: the keypad
  // stows, the entry card steps out of the way, every row grows a selection
  // circle and the total bar turns into a subtotal. Nothing is re-laid-out, so
  // the lines you're picking stay exactly where you were already looking.
  //
  // It stays a read-only lens — while it's on, the row's tap toggles instead of
  // editing and the context menu is gone entirely, so there's no Edit, no
  // Delete, and no "Use as reference" firing at a draft that isn't on screen.
  const [selectMode, setSelectMode] = useState(false);
  const [picked, setPicked] = useState<string[]>([]);

  const pickedSet = useMemo(() => new Set(picked), [picked]);
  const subtotal = entries.reduce((a, e) => (pickedSet.has(e.id) ? a + e.value : a), 0);
  const allPicked = entries.length > 0 && picked.length === entries.length;

  /** `seed` is the row a long-press started from, ticked on entry. */
  function startSelect(seed?: Entry) {
    Haptic.select();
    // the draft itself is left alone — it's still there when Done gives the
    // card back — but a live note field would keep the system keyboard up over
    // a screen that no longer has anywhere to type
    noteLive.current = false;
    noteInputRef.current?.blur();
    setNoteOpen(false);
    setPicked(seed ? [seed.id] : []);
    setSelectMode(true);
    setPad(1, true); // the tick above already covered this
  }

  function endSelect() {
    Haptic.tap();
    setSelectMode(false);
    setPicked([]);
    setPad(0, true);
  }

  function togglePick(row: Entry) {
    Haptic.select();
    setPicked((p) => (p.includes(row.id) ? p.filter((x) => x !== row.id) : [...p, row.id]));
  }

  // Dragging the grabber down grows the list: the keypad shrinks, and because
  // the list is the only flexible child, everything between it and the keypad
  // travels with the finger. Horizontal slop fails the gesture so a stray sideways
  // drag doesn't nudge the pad, and the 8pt activation offset leaves the total's
  // long-press-to-copy intact.
  const padDrag = useMemo(
    () =>
      Gesture.Pan()
        // select mode owns the keypad's position — it stowed it on the way in
        // and gives it back on Done, so the drag can't fight it meanwhile
        .enabled(!selectMode)
        .activeOffsetY([-8, 8])
        .failOffsetX([-24, 24])
        .onBegin(() => {
          stowStart.set(stow.get());
        })
        .onUpdate((e) => {
          if (padHeight <= 0) return;
          const v = stowStart.get() + e.translationY / padHeight;
          stow.set(v < 0 ? 0 : v > 1 ? 1 : v);
        })
        .onEnd((e) => {
          if (padHeight <= 0) return;
          const next =
            Math.abs(e.velocityY) > PAD_FLING
              ? e.velocityY > 0
                ? 1
                : 0
              : stow.get() > 0.5
                ? 1
                : 0;
          stow.set(withTiming(next, PAD_SETTLE));
          // Only when it actually landed somewhere else — a drag that snaps back
          // shouldn't fire a haptic.
          if (next !== stowStart.get()) runOnJS(syncPad)(next === 1);
        }),
    // the two shared values never change identity, so listing them costs
    // nothing — and keeps this component free of lint suppressions, which is
    // what lets the React Compiler memoise the screen at all (a single
    // suppression makes it skip the whole component)
    [padHeight, syncPad, selectMode, stow, stowStart],
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
    noteLive.current = false;
    noteInputRef.current?.blur();
    setDraft('');
    setNote('');
    setNoteOpen(false);
    setEditingId(null);
  }

  // The draft line belongs to the tab it was typed on. Opening a saved
  // calculation — or starting a fresh one — swaps `entries` out from under the
  // editor, but the draft, its note and the row being edited are local to this
  // screen and used to survive the swap: the previous tab's half-typed line sat
  // on the card over an empty tab, and any reference token in it pointed at a
  // line that no longer existed, so it rendered as a dangling "#?" pill.
  // Keyed on tabEpoch rather than activeId because a new tab started from an
  // already-unsaved one leaves activeId null on both sides (see tally-store).
  // Sits below clearDraft on purpose: the React Compiler won't memoise a
  // component whose effect reaches a hoisted function above its declaration.
  const firstEpoch = useRef(true);
  useEffect(() => {
    if (firstEpoch.current) {
      firstEpoch.current = false; // mount: nothing has been swapped yet
      return;
    }
    clearDraft();
  }, [tabEpoch]);

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
    noteLive.current = false; // same teardown race as clearDraft, one row over
    noteInputRef.current?.blur();
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

  // ---- sharing ----
  // Snapshot the tab to the tally-share Worker (web/ in this repo) and hand
  // the returned link to the system share sheet. The snapshot is frozen at
  // this moment — later edits here don't travel.
  async function shareLink() {
    Haptic.tap();
    try {
      await shareCalculation({ name: tabName, tags, entries, accent });
    } catch {
      Alert.alert('Couldn’t create the link', 'Check your connection and try again.');
    }
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
  // Two bar buttons. Trailing edge: the More menu (HIG "Toolbars" — when a
  // screen has more actions than the bar should show, collapse them into a
  // single `ellipsis` menu rather than lining symbols up across the bar).
  // Leading edge: Saved calculations — the one destination worth a direct
  // door (this is the root screen, so the slot isn't fighting a back button).
  // It stays in the menu too, where its label carries the count. The
  // title is left as plain text: it used to be a pull-down, but the chevron
  // beside it had to be a sibling of the Menu (a ReactNode label renders
  // nothing inside the nav bar's title view), so tapping the chevron — the
  // part that advertises the menu — did nothing. A title that isn't a control
  // shouldn't wear one.
  //
  // The symbol is bare `ellipsis`, not `ellipsis.circle`: a bar button already
  // sits in its own container, so a circle-variant symbol draws a second ring
  // inside the first. Same reason Select lost `checkmark.circle` here and
  // moved into the menu, where its symbol has no container to fight with.
  const renderSavedButton = () => (
    <Host style={{ width: 44, height: 44 }}>
      {/* the icon is the button's label (children, not `label=`): a string-label
          Button hit-tests only the glyph, so sizing the label itself is what
          makes the whole 44pt box tappable — same as the Saved screen's "+" */}
      <Button
        onPress={() => {
          Haptic.tap();
          router.push('/saved');
        }}>
        <Image
          systemName="tray.full"
          size={17}
          color={t.accentInk}
          modifiers={[
            frame({ width: 44, height: 44 }),
            contentShape(shapes.rectangle()),
            accessibilityLabel('Saved calculations'),
          ]}
        />
      </Button>
    </Host>
  );

  const renderMenu = () => (
    <Host style={{ width: 44, height: 44 }}>
      <Menu
        // A ReactNode label, not `label="More" systemImage="ellipsis"`: a
        // string-label Menu hit-tests only the glyph itself — frame/contentShape
        // on the Menu wrap it without growing the tappable label, so the bar's
        // capsule was decoration and taps beside the dots fell through. Sizing
        // the *label* (the Σ chip's pattern) makes the whole 44pt box tappable.
        label={
          <Image
            systemName="ellipsis"
            size={17}
            color={t.accentInk}
            modifiers={[
              frame({ width: 44, height: 44 }),
              contentShape(shapes.rectangle()),
              accessibilityLabel('Calculation options'),
            ]}
          />
        }>
        {/* what you can do to this calculation… */}
        <Button label="Rename & tags…" systemImage="pencil" onPress={() => setSaveOpen(true)} />
        <Button label="Copy total" systemImage="doc.on.doc" onPress={() => copyTotal(total)} />
        {entries.length > 0 && (
          <Button label="Share link…" systemImage="square.and.arrow.up" onPress={() => void shareLink()} />
        )}
        {entries.length > 1 && (
          <Button label="Select lines…" systemImage="checkmark.circle" onPress={() => startSelect()} />
        )}
        <Divider />
        {/* …starting a fresh one (medium impact: it clears the working tab)… */}
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
        {/* …and where else to go */}
        <Button
          label={tabs.length > 0 ? `Saved calculations (${tabs.length})` : 'Saved calculations'}
          systemImage="tray.full"
          onPress={() => router.push('/saved')}
        />
        <Button label="Settings" systemImage="gearshape" onPress={() => router.push('/settings')} />
      </Menu>
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
              onChangeText={(v) => {
                if (noteLive.current) setNote(v);
              }}
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
                        frame({ width: 36, height: 28 }),
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
        {showRes && <Text style={[styles.resTxt, { color: t.accentInk }]}>= {Calc.fmt(preview)}</Text>}
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

          The title just names the calculation. Everything that acts on it lives
          in the More menu on the trailing edge, the way HIG "Toolbars" asks a
          screen to handle more actions than the bar can comfortably show; the
          Saved archive also gets its own leading-edge button as the quick way
          back to filed calculations. */}
      <Stack.Screen
        options={{
          headerShown: true,
          headerTransparent: true,
          headerShadowVisible: false,
          headerTintColor: t.accentInk,
          // in select mode the title reports the count, so the answer and the
          // tally of what produced it sit at opposite ends of the screen
          title: selectMode
            ? picked.length > 0
              ? `${picked.length} selected`
              : 'Select lines'
            : tabName || 'New calculation',
          headerTitleStyle: { color: t.ink, fontFamily: TallyFonts.sansSemi },
          // select mode's items are native bar items, declared just below with
          // Stack.Toolbar — so the hosted views come off both slots here
          headerLeft: selectMode ? undefined : renderSavedButton,
          headerRight: selectMode ? undefined : renderMenu,
        }}
      />

      {/* Select mode borrows both bar slots, the way Mail and Photos do: Select
          All on the leading edge, the confirming action on the trailing one.
          They are real UIBarButtonItems (Stack.Toolbar), not SwiftUI hosts: the
          bar sizes each to its label and draws the one container HIG "Toolbars"
          wants. A hosted Button had to be given a width by hand, and the tick's
          own prominent style drew a second, accent circle inside the bar's
          capsule. `prominent` is the style HIG names for "key actions such as
          Done": the bar tints its own container, so a bare `checkmark` is all
          the item supplies — no `.circle` variant, no style of its own. */}
      {selectMode && (
        <>
          <Stack.Toolbar placement="left">
            <Stack.Toolbar.Button
              tintColor={t.accentInk}
              onPress={() => {
                Haptic.select();
                setPicked(allPicked ? [] : entries.map((e) => e.id));
              }}>
              {allPicked ? 'Deselect All' : 'Select All'}
            </Stack.Toolbar.Button>
          </Stack.Toolbar>
          <Stack.Toolbar placement="right">
            <Stack.Toolbar.Button
              icon="checkmark"
              variant="prominent"
              tintColor={t.accentSolid}
              accessibilityLabel="Done selecting"
              onPress={endSelect}
            />
          </Stack.Toolbar>
        </>
      )}

      {/* the running list — GroupedList, the app's one list surface (see
          components/tally/grouped-list) */}
      {entries.length === 0 ? (
        <View style={styles.empty}>
          <Text style={[styles.emptyTitle, { color: t.ink2 }]}>Nothing tallied yet.</Text>
          {/* was "hit ↵" — Geist has no glyph for U+21B5, so it rendered in a
              substituted font and VoiceOver read it as nothing useful */}
          <Text style={[styles.emptyHint, { color: t.ink3 }]}>Tap a number, name it, then hit return</Text>
        </View>
      ) : (
        <GroupedList ref={listWrapRef} trimTop style={styles.listGap}>
          {entries.map((e, i) => (
            <SwipeRow
              key={e.id}
              entry={e}
              first={i === 0}
              selected={e.id === editingId}
              showExpr={showExpr}
              justAdded={e.id === justAddedId}
              nameFor={nameFor}
              theme={t}
              canReference={editIndex < 0 || i < editIndex}
              selectMode={selectMode}
              picked={pickedSet.has(e.id)}
              onEdit={editRow}
              onDelete={deleteRow}
              onSelect={startSelect}
              onTogglePick={togglePick}
              onReference={(row) => insertRef(row.id, row.note)}
            />
          ))}
        </GroupedList>
      )}

      {/* The seam between reviewing (the list) and entering (card + keypad), and
          the handle for the keypad: drag anywhere on this block, or tap the
          grabber. It renders even with the total switched off, so there's always
          somewhere to grab. */}
      <GestureDetector gesture={padDrag}>
        <View>
          {/* nothing to grab while selecting — the keypad isn't the user's to
              move until Done gives it back */}
          {!selectMode && (
            <Pressable
              style={styles.grabHit}
              onPress={() => setPad(padStowed ? 0 : 1)}
              hitSlop={{ top: 12, bottom: 12 }}
              accessibilityRole="button"
              accessibilityLabel={padStowed ? 'Show keypad' : 'Hide keypad'}
              accessibilityHint="Hiding the keypad gives the list of amounts the rest of the screen">
              {/* accent while stowed: the app's "active" colour everywhere else,
                  so a tinted grabber reads as "something is put away here" */}
              <View style={[styles.grab, { backgroundColor: padStowed ? t.accentInk : t.ink3 }]} />
            </Pressable>
          )}

          {/* The running total — long-press to copy. In select mode this same
              bar is the answer: it counts what's ticked and reads out their
              subtotal, in the accent so it's plainly not the tab's total. It
              shows even when the total is switched off in Settings, because in
              select mode it's the whole point of the mode. */}
          {(showTotal || selectMode) && (
            <Pressable
              onLongPress={() => copyTotal(selectMode ? subtotal : total)}
              delayLongPress={350}
              style={({ pressed }) => [
                styles.total,
                { borderTopColor: t.line },
                pressed && styles.totalPressed,
              ]}>
              <Animated.Text
                key={copied ? 'copied' : selectMode ? 'picked' : 'total'}
                entering={FadeIn.duration(200)}
                style={[styles.tLab, { color: copied ? t.accentInk : t.ink2 }]}
                numberOfLines={1}>
                {/* the ✓ that used to trail this is gone: it's the last stray text
                    glyph, and the accent colour plus the fade already read as
                    confirmation without leaning on a substituted font */}
                {copied
                  ? 'Copied'
                  : selectMode
                    ? picked.length > 0
                      ? `${picked.length} of ${entries.length} selected`
                      : 'Tap lines to add them up'
                    : 'Total'}
              </Animated.Text>
              {/* the total lands on its new value outright — no count-up tween,
                  no scale pulse: it's a number you read, not an event */}
              <Text
                style={[
                  styles.tBig,
                  { color: selectMode ? (picked.length > 0 ? t.accentInk : t.ink3) : t.ink },
                ]}
                maxFontSizeMultiplier={1.4}>
                {Calc.fmt(selectMode ? subtotal : total)}
              </Text>
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
        // `gone`, not unmounted: select mode is a detour, and tearing the glass
        // surface down and rebuilding it on the way back is both a visible
        // flicker and the loss of whatever was half-typed in the card
        style={selectMode ? styles.gone : undefined}
        accessible={padStowed && !selectMode}
        accessibilityRole={padStowed ? 'button' : undefined}
        accessibilityLabel={padStowed ? 'Show keypad' : undefined}>
        {LIQUID ? (
          <GlassView
            glassEffectStyle="regular"
            colorScheme={themeMode}
            style={[styles.entry, styles.entryGlass, { borderColor: flash || editingId ? t.accentInk : t.line }]}>
            {entryBody}
          </GlassView>
        ) : (
          <View
            style={[styles.entry, { backgroundColor: t.card, borderColor: flash || editingId ? t.accentInk : t.line }]}>
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

  // Full-bleed on purpose: the scroll indicator rides the host's trailing edge,
  // so padding here parked it 16pt in from the screen edge. The card's inset
  // from the screen edge lives on the rows instead (CARD_INSET in SwipeRow).
  list: { flex: 1 },
  listHost: { flex: 1, backgroundColor: 'transparent' },
  // trimTop drops SwiftUI's ~35pt first-section margin; this is the gap the
  // screen actually wants between the floating nav bar and the card
  listGap: { marginTop: 8 },

  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12, padding: 20 },
  emptyTitle: { fontFamily: TallyFonts.serif, fontSize: 20, lineHeight: 22, textAlign: 'center', maxWidth: 180 },
  emptyHint: { fontFamily: TallyFonts.sans, fontSize: 13, lineHeight: 19 },

  // Full-width strip so the keypad handle is easy to hit; the strip is drawn
  // small (20pt) to keep the seam tight, and the 12pt hitSlop each way makes
  // up the 44pt HIG target on its short axis. The grabber's radius is clamped
  // to half its 4pt height whatever we ask for, so 4 reads as the pill it is.
  grabHit: { height: 20, alignItems: 'center', justifyContent: 'center' },
  grab: { width: 32, height: 4, borderRadius: 4, opacity: 0.5 },

  total: {
    marginHorizontal: 20,
    marginTop: 0,
    marginBottom: 8,
    paddingTop: 8,
    borderTopWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    gap: 12,
  },
  totalPressed: { opacity: 0.6 },
  tLab: { fontFamily: TallyFonts.sansMedium, fontSize: 13 },
  tBig: { fontFamily: TallyFonts.monoSemi, fontSize: 20, fontVariant: ['tabular-nums'], letterSpacing: -0.2 },


  entry: {
    marginHorizontal: 16,
    marginBottom: 8,
    paddingTop: 12,
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
  entryTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12, minHeight: 24 },
  entryTopLhs: { flex: 1, minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 8 },
  // the Σ "use a saved total" chip — sized to match the note chip's height;
  // the SwiftUI Menu inside owns the tap
  refChip: { borderRadius: 8, overflow: 'hidden' },
  refHost: { width: 36, height: 28 },
  chip: { paddingVertical: 4, paddingHorizontal: 12, borderRadius: 8, maxWidth: 120 },
  chipGhost: { paddingVertical: 4, paddingHorizontal: 12, borderRadius: 8 },
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
