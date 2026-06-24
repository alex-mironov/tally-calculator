// index.tsx — Tally, the running-tab calculator (2026 refresh). One screen:
// a nameable tab, a labelled list of amounts, a live total, the in-progress
// entry, optional tag chips, and the keypad. The ⋯ menu opens the Saved
// archive and Settings.
import { Button, Divider, Host, Image, List, Menu, Section } from '@expo/ui/swift-ui';
import {
  listRowSpacing,
  listSectionSpacing,
  listStyle,
  scrollContentBackground,
  tint,
} from '@expo/ui/swift-ui/modifiers';
import * as Clipboard from 'expo-clipboard';
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
import { SaveSheet } from '@/components/tally/save-sheet';
import { SwipeRow } from '@/components/tally/swipe-row';
import { TagChip } from '@/components/tally/tags';
import { TallyFonts } from '@/constants/tally-theme';
import * as Calc from '@/lib/calc-engine';
import { uid, useTally, type Entry } from '@/lib/tally-store';

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
    tabName,
    tags,
    toggleTag,
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
  const [addingTag, setAddingTag] = useState(false);
  const [tagDraft, setTagDraft] = useState('');

  const noteInputRef = useRef<RNTextInput>(null);
  const tagInputRef = useRef<RNTextInput>(null);

  useEffect(() => {
    if (noteOpen) noteInputRef.current?.focus();
  }, [noteOpen]);
  useEffect(() => {
    if (addingTag) tagInputRef.current?.focus();
  }, [addingTag]);

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

  function deleteRow(id: string) {
    setEntries((l) => l.filter((x) => x.id !== id));
    if (editingId === id) clearDraft();
  }

  // Long-press the running total → copy the plain number to the clipboard so it
  // pastes cleanly into spreadsheets and other apps.
  async function copyTotal() {
    await Clipboard.setStringAsync(total.toFixed(2));
    setCopied(true);
    setTimeout(() => setCopied(false), 1200);
  }

  function finishTag() {
    setAddingTag(false);
    const name = addCatalogTag(tagDraft);
    if (name && !tags.includes(name)) toggleTag(name);
    setTagDraft('');
  }

  return (
    <View style={[styles.root, { backgroundColor: t.screen, paddingTop: insets.top }]}>
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
          <Host matchContents style={styles.menuHost}>
            <Menu
              label={<Image systemName="ellipsis" size={22} color={t.ink2} />}
              modifiers={[tint('#FFFFFF')]}>
              <Button label="New calculation" systemImage="plus" onPress={() => newTab()} />
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
          <Text style={[styles.emptyHint, { color: t.ink3 }]}>Tap a number, name it, hit ↵</Text>
        </View>
      ) : (
        <Host style={styles.list}>
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
                  theme={t}
                  onEdit={editRow}
                  onDelete={deleteRow}
                />
              ))}
            </Section>
          </List>
        </Host>
      )}

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
          <Text style={[styles.tLab, { color: copied ? t.accent : t.ink2 }]}>
            {copied ? 'Copied ✓' : 'Total'}
          </Text>
          <Text style={[styles.tBig, { color: t.ink }]}>{Calc.fmt(total)}</Text>
        </Pressable>
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
          {showRes && <Text style={[styles.resTxt, { color: t.accent }]}>= {Calc.fmt(preview)}</Text>}
        </View>
        <Text style={[styles.draftBig, { color: draft ? t.ink : t.ink3 }]} numberOfLines={1} allowFontScaling={false}>
          {draft || '0'}
        </Text>
      </View>

      {/* tag the current tab — toggles tags live before the tab is even saved */}
      {entries.length > 0 && (
        <View style={styles.tagRowWrap}>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.tagRow}>
            <Text style={[styles.tagLead, { color: t.ink3 }]}>TAG</Text>
            {catalog.map((tg) => (
              <TagChip
                key={tg}
                name={tg}
                theme={t}
                selected={tags.includes(tg)}
                onPress={() => toggleTag(tg)}
              />
            ))}
            {addingTag ? (
              <TextInput
                ref={tagInputRef}
                style={[styles.tagInput, { color: t.ink, borderColor: t.accent, backgroundColor: t.card }]}
                value={tagDraft}
                placeholder="new tag…"
                placeholderTextColor={t.ink3}
                onChangeText={setTagDraft}
                onBlur={finishTag}
                onSubmitEditing={finishTag}
                returnKeyType="done"
                maxLength={22}
                autoCapitalize="words"
              />
            ) : (
              <Pressable style={[styles.tagAdd, { backgroundColor: t.accent2 }]} onPress={() => setAddingTag(true)}>
                <Text style={[styles.tagAddText, { color: t.accentInk }]}>+ tag</Text>
              </Pressable>
            )}
          </ScrollView>
        </View>
      )}

      <Keypad theme={t} onPress={press} bottomInset={insets.bottom} />

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

  menuWrap: { position: 'relative', marginTop: 2 },
  menuHost: {},
  countBadge: {
    position: 'absolute',
    top: -5,
    right: -7,
    minWidth: 15,
    height: 15,
    paddingHorizontal: 3,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  countBadgeText: { color: '#fff', fontFamily: TallyFonts.mono, fontSize: 9, lineHeight: 11 },

  list: { flex: 1, paddingHorizontal: 16 },

  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 10, padding: 20 },
  emptyTitle: { fontFamily: TallyFonts.serif, fontSize: 20, lineHeight: 22, textAlign: 'center', maxWidth: 200 },
  emptyHint: { fontFamily: TallyFonts.sans, fontSize: 13, lineHeight: 19 },

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

  editbar: { marginHorizontal: 16, marginBottom: 6, flexDirection: 'row', alignItems: 'center', gap: 10 },
  editText: { fontSize: 12, fontFamily: TallyFonts.sans },
  editAction: { marginLeft: 'auto' },
  miniLink: { fontSize: 12, fontFamily: TallyFonts.sansSemi, textDecorationLine: 'underline' },

  entry: {
    marginHorizontal: 16,
    marginBottom: 10,
    paddingTop: 12,
    paddingBottom: 14,
    paddingHorizontal: 16,
    borderWidth: 1,
    borderRadius: 20,
    gap: 6,
    shadowColor: '#000',
    shadowOpacity: 0.08,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 8 },
    elevation: 2,
  },
  entryTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 10, minHeight: 24 },
  chip: { paddingVertical: 5, paddingHorizontal: 10, borderRadius: 9, maxWidth: 160 },
  chipGhost: { paddingVertical: 5, paddingHorizontal: 10, borderRadius: 9 },
  chipText: { fontFamily: TallyFonts.sansSemi, fontSize: 12.5 },
  noteInput: { flex: 1, fontFamily: TallyFonts.sansSemi, fontSize: 14, padding: 0 },
  resTxt: { fontFamily: TallyFonts.monoMedium, fontSize: 13 },
  draftBig: {
    fontFamily: TallyFonts.monoSemi,
    fontSize: 36,
    lineHeight: 40,
    textAlign: 'right',
    fontVariant: ['tabular-nums'],
    letterSpacing: -0.8,
  },

  tagRowWrap: { marginBottom: 10 },
  tagRow: { alignItems: 'center', gap: 7, paddingHorizontal: 16 },
  tagLead: { fontFamily: TallyFonts.mono, fontSize: 9.5, letterSpacing: 1.7, marginRight: 1 },
  tagAdd: { paddingVertical: 7, paddingHorizontal: 14, borderRadius: 999 },
  tagAddText: { fontFamily: TallyFonts.sansSemi, fontSize: 12.5 },
  tagInput: {
    width: 110,
    paddingVertical: 6,
    paddingHorizontal: 13,
    borderRadius: 20,
    borderWidth: 1,
    fontFamily: TallyFonts.sansSemi,
    fontSize: 12.5,
  },

});
