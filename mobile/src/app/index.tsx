// index.tsx — Tally, the running-tab calculator. One screen: a labelled list
// of amounts, a live total, the in-progress entry, and the keypad.
import { useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
  type TextInput as RNTextInput,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Keypad, type Key } from '@/components/tally/keypad';
import { TallyFonts } from '@/constants/tally-theme';
import * as Calc from '@/lib/calc-engine';
import { uid, useTally, type Entry } from '@/lib/tally-store';

export default function TallyScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { entries, setEntries, total, theme: t, themeMode, currency, showExpr, showTotal } = useTally();

  const [draft, setDraft] = useState('');
  const [note, setNote] = useState('');
  const [noteOpen, setNoteOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [split, setSplit] = useState(0);
  const [flash, setFlash] = useState(false);

  const listRef = useRef<ScrollView>(null);
  const noteInputRef = useRef<RNTextInput>(null);

  // keep the newest line in view
  useEffect(() => {
    listRef.current?.scrollToEnd({ animated: true });
  }, [entries.length]);

  // focus the note field the moment it opens
  useEffect(() => {
    if (noteOpen) noteInputRef.current?.focus();
  }, [noteOpen]);

  const preview = Calc.evaluate(draft);
  const showRes = preview != null && Calc.hasOperator(draft);
  const editingRow = entries.find((e) => e.id === editingId);

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
    clearDraft();
  }

  function editRow(row: Entry) {
    setDraft(row.expr || String(row.value));
    setNote(row.note || '');
    setEditingId(row.id);
    setNoteOpen(false);
  }

  function deleteEditing() {
    setEntries((l) => l.filter((x) => x.id !== editingId));
    clearDraft();
  }

  function clearTab() {
    setEntries([]);
    clearDraft();
    setSplit(0);
  }

  return (
    <View style={[styles.root, { backgroundColor: t.screen, paddingTop: insets.top }]}>
      <StatusBar style={themeMode === 'dark' ? 'light' : 'dark'} />

      {/* header: item count · clear · settings */}
      <View style={styles.head}>
        <Text style={[styles.sesMeta, { color: t.ink3 }]}>
          {entries.length} ITEM{entries.length === 1 ? '' : 'S'}
        </Text>
        <View style={styles.headRight}>
          {entries.length > 0 && (
            <Pressable onPress={clearTab} hitSlop={8}>
              <Text style={[styles.clear, { color: t.ink3 }]}>CLEAR</Text>
            </Pressable>
          )}
          <Pressable onPress={() => router.push('/settings')} hitSlop={8} accessibilityLabel="Settings">
            <SettingsGlyph color={t.ink2} fill={t.screen} />
          </Pressable>
        </View>
      </View>

      {/* the running list */}
      <ScrollView ref={listRef} style={styles.list} contentContainerStyle={styles.listContent}>
        {entries.length === 0 ? (
          <View style={styles.empty}>
            <Text style={[styles.emptyKicker, { color: t.ink3 }]}>EMPTY TAB</Text>
            <Text style={[styles.emptyTitle, { color: t.ink2 }]}>Nothing tallied yet.</Text>
            <Text style={[styles.emptyHint, { color: t.ink3 }]}>Tap a number, name it, hit ↵</Text>
          </View>
        ) : (
          entries.map((e) => {
            const sel = e.id === editingId;
            return (
              <Pressable
                key={e.id}
                onPress={() => editRow(e)}
                style={[
                  styles.row,
                  { borderBottomColor: t.line },
                  sel && { backgroundColor: t.rowSel, borderRadius: 10, borderBottomColor: 'transparent' },
                ]}>
                <View style={styles.rowLhs}>
                  <Text
                    style={[
                      styles.note,
                      { color: e.note ? t.ink2 : t.ink3 },
                      !e.note && { fontStyle: 'italic' },
                    ]}>
                    {e.note || 'No note'}
                  </Text>
                  {!!e.expr && showExpr && (
                    <Text style={[styles.expr, { color: t.accentInk, backgroundColor: t.accent2 }]}>{e.expr}</Text>
                  )}
                </View>
                <Text style={[styles.amt, { color: t.ink }]}>{Calc.fmt(e.value)}</Text>
              </Pressable>
            );
          })
        )}
      </ScrollView>

      {/* live total — tap to split */}
      {showTotal && (
        <Pressable
          onPress={() => setSplit((s) => (s === 0 ? 2 : s))}
          style={[styles.total, { borderTopColor: t.line }]}>
          <Text style={[styles.tLab, { color: t.ink3 }]}>
            RUNNING TOTAL{split > 0 ? ' · ÷' + split : ''}
          </Text>
          <View style={styles.totalRight}>
            <Text style={[styles.tBig, { color: t.ink2 }]}>
              {currency}
              {Calc.fmt(total)}
            </Text>
            {split > 0 && (
              <Text style={[styles.tPer, { color: t.accentInk }]}>
                {currency}
                {Calc.fmt(total / split)} each
              </Text>
            )}
          </View>
        </Pressable>
      )}

      {/* split stepper */}
      {split > 0 && (
        <View style={styles.splitbar}>
          <Pressable
            style={[styles.stepBtn, { borderColor: t.line }]}
            onPress={() => setSplit((s) => Math.max(0, s - 1))}>
            <Text style={[styles.stepGlyph, { color: t.ink }]}>−</Text>
          </Pressable>
          <Text style={[styles.splitLabel, { color: t.ink2 }]}>{split} ways</Text>
          <Pressable style={[styles.stepBtn, { borderColor: t.line }]} onPress={() => setSplit((s) => s + 1)}>
            <Text style={[styles.stepGlyph, { color: t.ink }]}>+</Text>
          </Pressable>
          <Pressable style={styles.splitDone} onPress={() => setSplit(0)}>
            <Text style={[styles.miniLink, { color: t.ink2 }]}>done</Text>
          </Pressable>
        </View>
      )}

      {/* edit affordances */}
      {editingId && (
        <View style={styles.editbar}>
          <Text style={[styles.editText, { color: t.ink2 }]}>
            Editing{' '}
            <Text style={{ color: t.ink, fontFamily: TallyFonts.sansBold }}>
              {editingRow?.note || 'this line'}
            </Text>
          </Text>
          <Pressable style={styles.editAction} onPress={deleteEditing}>
            <Text style={[styles.miniLink, { color: t.accent }]}>Delete</Text>
          </Pressable>
          <Pressable onPress={clearDraft}>
            <Text style={[styles.miniLink, { color: t.ink2 }]}>Cancel</Text>
          </Pressable>
        </View>
      )}

      {/* in-progress entry */}
      <View style={[styles.entry, { backgroundColor: t.card, borderColor: flash ? t.accent : t.line }]}>
        <View style={styles.entryTop}>
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
            />
          ) : note ? (
            <Pressable
              style={[styles.chip, { backgroundColor: t.accent2 }]}
              onPress={() => setNoteOpen(true)}>
              <Text style={[styles.chipText, { color: t.accentInk }]} numberOfLines={1}>
                {note}
              </Text>
            </Pressable>
          ) : (
            <Pressable style={[styles.chipGhost, { borderColor: t.line }]} onPress={() => setNoteOpen(true)}>
              <Text style={[styles.chipText, { color: t.ink3, fontFamily: TallyFonts.sansMedium }]}>+ note</Text>
            </Pressable>
          )}
          {showRes && <Text style={[styles.resTxt, { color: t.accent }]}>= {Calc.fmt(preview)}</Text>}
        </View>
        <Text style={[styles.draftBig, { color: draft ? t.ink : t.ink3 }]} numberOfLines={1} allowFontScaling={false}>
          {draft || '0'}
        </Text>
      </View>

      <Keypad theme={t} onPress={press} bottomInset={insets.bottom} />
    </View>
  );
}

/** The three-slider settings glyph from the prototype. */
function SettingsGlyph({ color, fill }: { color: string; fill: string }) {
  // Drawn with views so we don't pull in an SVG dependency.
  return (
    <View style={glyph.wrap}>
      {[
        { y: 3, cx: 14 },
        { y: 9, cx: 5 },
        { y: 15, cx: 10 },
      ].map((s, i) => (
        <View key={i} style={[glyph.track, { top: s.y, backgroundColor: color }]}>
          <View style={[glyph.knob, { left: s.cx, borderColor: color, backgroundColor: fill }]} />
        </View>
      ))}
    </View>
  );
}

const glyph = StyleSheet.create({
  wrap: { width: 19, height: 19 },
  track: { position: 'absolute', left: 1, right: 1, height: 1.6, borderRadius: 1 },
  knob: { position: 'absolute', top: -2.7, width: 6, height: 6, borderRadius: 3, borderWidth: 1.6 },
});

const styles = StyleSheet.create({
  root: { flex: 1 },
  head: {
    paddingHorizontal: 20,
    paddingTop: 2,
    paddingBottom: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  sesMeta: { fontFamily: TallyFonts.mono, fontSize: 11, letterSpacing: 1.5 },
  headRight: { flexDirection: 'row', alignItems: 'center', gap: 16 },
  clear: { fontFamily: TallyFonts.mono, fontSize: 11, letterSpacing: 0.9 },

  list: { flex: 1, paddingHorizontal: 16 },
  listContent: { flexGrow: 1, paddingVertical: 2 },
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 10,
    paddingVertical: 11,
    paddingHorizontal: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  rowLhs: { flex: 1, minWidth: 0 },
  note: { fontFamily: TallyFonts.sansMedium, fontSize: 15 },
  expr: {
    alignSelf: 'flex-start',
    fontFamily: TallyFonts.mono,
    fontSize: 10.5,
    paddingVertical: 1.5,
    paddingHorizontal: 6,
    borderRadius: 5,
    marginTop: 5,
    overflow: 'hidden',
  },
  amt: { fontFamily: TallyFonts.monoMedium, fontSize: 15, fontVariant: ['tabular-nums'], marginTop: 1 },

  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 10, padding: 20 },
  emptyKicker: { fontFamily: TallyFonts.mono, fontSize: 10, letterSpacing: 2, textTransform: 'uppercase' },
  emptyTitle: { fontFamily: TallyFonts.serif, fontSize: 26, lineHeight: 28, textAlign: 'center', maxWidth: 200 },
  emptyHint: { fontFamily: TallyFonts.sans, fontSize: 12.5, lineHeight: 19 },

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
  tLab: { fontFamily: TallyFonts.mono, fontSize: 10, letterSpacing: 1.6, textTransform: 'uppercase' },
  totalRight: { alignItems: 'flex-end' },
  tBig: { fontFamily: TallyFonts.monoSemi, fontSize: 22, fontVariant: ['tabular-nums'] },
  tPer: { fontFamily: TallyFonts.mono, fontSize: 10.5, marginTop: 2 },

  splitbar: { marginHorizontal: 16, marginBottom: 8, flexDirection: 'row', alignItems: 'center', gap: 8 },
  stepBtn: {
    width: 30,
    height: 30,
    borderRadius: 9,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  stepGlyph: { fontSize: 17, lineHeight: 19 },
  splitLabel: { minWidth: 56, textAlign: 'center', fontSize: 12.5, fontFamily: TallyFonts.sans },
  splitDone: { marginLeft: 'auto' },

  editbar: { marginHorizontal: 16, marginBottom: 6, flexDirection: 'row', alignItems: 'center', gap: 10 },
  editText: { fontSize: 12, fontFamily: TallyFonts.sans },
  editAction: { marginLeft: 'auto' },
  miniLink: { fontSize: 12, fontFamily: TallyFonts.sansSemi, textDecorationLine: 'underline' },

  entry: {
    marginHorizontal: 16,
    marginBottom: 10,
    paddingTop: 11,
    paddingBottom: 13,
    paddingHorizontal: 16,
    borderWidth: 1,
    borderRadius: 16,
    gap: 6,
  },
  entryTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 10, minHeight: 24 },
  chip: { paddingVertical: 5, paddingHorizontal: 10, borderRadius: 9, maxWidth: 160 },
  chipGhost: { paddingVertical: 5, paddingHorizontal: 10, borderRadius: 9, borderWidth: 1, borderStyle: 'dashed' },
  chipText: { fontFamily: TallyFonts.sansSemi, fontSize: 12.5 },
  noteInput: { flex: 1, fontFamily: TallyFonts.sansSemi, fontSize: 14, padding: 0 },
  resTxt: { fontFamily: TallyFonts.monoMedium, fontSize: 13 },
  draftBig: {
    fontFamily: TallyFonts.monoSemi,
    fontSize: 40,
    lineHeight: 44,
    textAlign: 'right',
    fontVariant: ['tabular-nums'],
    letterSpacing: -0.8,
  },
});
