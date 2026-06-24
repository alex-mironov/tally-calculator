// swipe-row.tsx — a single line in the running tab, rendered as a native
// SwiftUI list row. Swipe left for a native Delete action, long-press for a
// native context menu (Edit / Delete), tap to edit. The row's visual is the
// existing RN layout embedded via RNHostView, so the custom fonts and the expr
// chip survive while the gestures are pure SwiftUI. Must be rendered inside a
// SwiftUI `List` + `Section` (see index.tsx) — SwipeActions only works there.
import { Button, ContextMenu, RNHostView, SwipeActions } from '@expo/ui/swift-ui';
import { listRowBackground, listRowInsets, listRowSeparator } from '@expo/ui/swift-ui/modifiers';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { TallyFonts, type TallyTheme } from '@/constants/tally-theme';
import * as Calc from '@/lib/calc-engine';
import { type Entry } from '@/lib/tally-store';

type Props = {
  entry: Entry;
  selected: boolean;
  showExpr: boolean;
  /** the final row in the list draws no divider beneath it */
  last?: boolean;
  theme: TallyTheme;
  onEdit: (e: Entry) => void;
  onDelete: (id: string) => void;
};

export function SwipeRow({ entry: e, selected, showExpr, last, theme: t, onEdit, onDelete }: Props) {
  return (
    <SwipeActions
      modifiers={[
        listRowInsets({ top: 0, leading: 0, bottom: 0, trailing: 0 }),
        listRowBackground(t.screen),
        listRowSeparator('hidden'),
      ]}>
      {/* long-press → native context menu; the row itself is the trigger */}
      <ContextMenu>
        <ContextMenu.Items>
          <Button label="Edit" systemImage="pencil" onPress={() => onEdit(e)} />
          <Button label="Delete" systemImage="trash" role="destructive" onPress={() => onDelete(e.id)} />
        </ContextMenu.Items>
        <ContextMenu.Trigger>
          <RNHostView matchContents>
            <Pressable
              onPress={() => onEdit(e)}
              style={({ pressed }) => [
                styles.row,
                { backgroundColor: t.screen, borderBottomColor: t.line },
                (selected || last) && { borderBottomColor: 'transparent' },
                selected && { backgroundColor: t.rowSel, borderRadius: 10 },
                pressed && styles.pressed,
              ]}>
              <View style={styles.rowLhs}>
                <Text
                  style={[styles.note, { color: e.note ? t.ink2 : t.ink3 }, !e.note && styles.noteEmpty]}>
                  {e.note || 'No note'}
                </Text>
                {!!e.expr && showExpr && (
                  <Text style={[styles.expr, { color: t.accentInk, backgroundColor: t.accent2 }]}>{e.expr}</Text>
                )}
              </View>
              <Text style={[styles.amt, { color: t.ink }]}>{Calc.fmt(e.value)}</Text>
            </Pressable>
          </RNHostView>
        </ContextMenu.Trigger>
      </ContextMenu>

      {/* swipe left → native Delete */}
      <SwipeActions.Actions edge="trailing">
        <Button label="Delete" systemImage="trash" role="destructive" onPress={() => onDelete(e.id)} />
      </SwipeActions.Actions>
    </SwipeActions>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 10,
    paddingVertical: 5,
    paddingHorizontal: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  pressed: { opacity: 0.6 },
  rowLhs: { flex: 1, minWidth: 0 },
  note: { fontFamily: TallyFonts.sansMedium, fontSize: 13.5 },
  noteEmpty: { fontStyle: 'italic' },
  expr: {
    alignSelf: 'flex-start',
    fontFamily: TallyFonts.mono,
    fontSize: 10,
    paddingVertical: 1,
    paddingHorizontal: 5,
    borderRadius: 5,
    marginTop: 3,
    overflow: 'hidden',
  },
  amt: { fontFamily: TallyFonts.monoMedium, fontSize: 13.5, fontVariant: ['tabular-nums'], marginTop: 1 },
});
