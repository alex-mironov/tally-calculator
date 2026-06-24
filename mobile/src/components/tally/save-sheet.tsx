// save-sheet.tsx — the primary "name + tag" sheet for the running tab. Opens
// from the header title on the calculator and from "Save this tab" on the Saved
// archive. Edits flow straight into the store (live tabName + tags); the Save
// button commits the snapshot via saveDraft().
import { useEffect, useRef, useState } from 'react';
import {
  Keyboard,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
  type TextInput as RNTextInput,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { TagToggleGrid } from '@/components/tally/tags';
import { TallyFonts } from '@/constants/tally-theme';
import { useTally } from '@/lib/tally-store';

export function SaveSheet({ visible, onClose }: { visible: boolean; onClose: () => void }) {
  const insets = useSafeAreaInsets();
  const {
    theme: t,
    tabName,
    setTabName,
    tags,
    setTags,
    catalog,
    addCatalogTag,
    saveDraft,
    activeId,
    entries,
  } = useTally();

  const nameRef = useRef<RNTextInput>(null);
  const [keyboardUp, setKeyboardUp] = useState(false);

  // Focus the name field shortly after the sheet finishes animating in. The
  // field binds straight to the store, so the live title updates as you type.
  useEffect(() => {
    if (!visible) return;
    const id = setTimeout(() => nameRef.current?.focus(), 250);
    return () => clearTimeout(id);
  }, [visible]);

  // While the keyboard is up it already covers the home-indicator area, so the
  // safe-area bottom inset would just be dead space under the Save button.
  useEffect(() => {
    const show = Keyboard.addListener('keyboardWillShow', () => setKeyboardUp(true));
    const hide = Keyboard.addListener('keyboardWillHide', () => setKeyboardUp(false));
    return () => {
      show.remove();
      hide.remove();
    };
  }, []);

  function handleSave() {
    saveDraft();
    onClose();
  }

  const canSave = entries.length > 0;
  const isNew = activeId == null;

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        style={styles.fill}>
        <Pressable style={styles.scrim} onPress={onClose} />
        <View
          style={[
            styles.sheet,
            { backgroundColor: t.screen, paddingBottom: keyboardUp ? 16 : insets.bottom + 16 },
          ]}>
          <View style={[styles.grab, { backgroundColor: t.line }]} />

          <Text style={[styles.title, { color: t.ink }]}>{isNew ? 'Save tab' : 'Tab details'}</Text>
          <Text style={[styles.sub, { color: t.ink2 }]}>Name it and choose any tags.</Text>

          <Text style={[styles.fieldLab, { color: t.ink3 }]}>NAME</Text>
          <TextInput
            ref={nameRef}
            style={[styles.nameInput, { color: t.ink, borderBottomColor: t.accent }]}
            value={tabName}
            placeholder="Name this tab…"
            placeholderTextColor={t.ink3}
            onChangeText={setTabName}
            onSubmitEditing={canSave ? handleSave : undefined}
            returnKeyType="done"
          />

          <Text style={[styles.fieldLab, styles.tagsLab, { color: t.ink3 }]}>TAGS</Text>
          <TagToggleGrid
            theme={t}
            catalog={catalog}
            value={tags}
            onChange={setTags}
            onCreate={addCatalogTag}
          />

          <Pressable
            style={[styles.saveBtn, { backgroundColor: t.accent }, !canSave && styles.saveBtnOff]}
            onPress={handleSave}
            disabled={!canSave}>
            <Text style={styles.saveBtnText}>{isNew ? 'Save this tab' : 'Done'}</Text>
          </Pressable>
        </View>
      </KeyboardAvoidingView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, justifyContent: 'flex-end' },
  scrim: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(20,12,8,0.34)' },
  sheet: {
    borderTopLeftRadius: 22,
    borderTopRightRadius: 22,
    paddingTop: 8,
    paddingHorizontal: 20,
  },
  grab: { width: 40, height: 4, borderRadius: 2, alignSelf: 'center', marginBottom: 14 },
  title: { fontFamily: TallyFonts.serif, fontSize: 22, letterSpacing: -0.3 },
  sub: { fontFamily: TallyFonts.sans, fontSize: 13, marginTop: 3 },

  fieldLab: { fontFamily: TallyFonts.mono, fontSize: 10, letterSpacing: 1.6, marginTop: 18, marginBottom: 8 },
  tagsLab: { marginTop: 22 },
  nameInput: {
    fontFamily: TallyFonts.serif,
    fontSize: 20,
    letterSpacing: -0.2,
    borderBottomWidth: 1.5,
    paddingVertical: 4,
  },

  saveBtn: { marginTop: 26, paddingVertical: 14, borderRadius: 14, alignItems: 'center' },
  saveBtnOff: { opacity: 0.4 },
  saveBtnText: { color: '#fff', fontFamily: TallyFonts.sansSemi, fontSize: 15 },
});
