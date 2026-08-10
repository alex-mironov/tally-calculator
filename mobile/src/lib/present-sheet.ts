// present-sheet.ts — thin JS wrapper over the native `TallySheet` SwiftUI module
// (modules/tally-sheet): the "name + tags" form, and the multi-select lens over
// a tab's lines. On platforms without the native module both resolve to a no-op.
//
// Both sheets are system-drawn, so the theme barely crosses over: the accent
// tints their controls and the mode picks the colour scheme. Everything else is
// the platform's.
import {
  presentSelection,
  presentSheet,
  type SelectionResult,
  type SelectionRow,
  type SheetResult,
} from '../../modules/tally-sheet';
import type { TallyTheme } from '@/constants/tally-theme';

export type { SelectionResult, SelectionRow, SheetResult };

export type PresentTagSheetArgs = {
  theme: TallyTheme;
  isDark: boolean;
  title: string;
  subtitle: string;
  /** show the name field (Save tab) or tags only (Edit tags) */
  showName: boolean;
  name?: string;
  namePlaceholder?: string;
  catalog: string[];
  selected: string[];
  primaryLabel: string;
  /** gate the primary button (e.g. nothing to save yet) */
  canSave?: boolean;
};

export function presentTagSheet(a: PresentTagSheetArgs): Promise<SheetResult> {
  return presentSheet({
    title: a.title,
    subtitle: a.subtitle,
    showName: a.showName,
    name: a.name ?? '',
    namePlaceholder: a.namePlaceholder ?? '',
    catalog: a.catalog,
    selected: a.selected,
    primaryLabel: a.primaryLabel,
    canSave: a.canSave ?? true,
    isDark: a.isDark,
    colors: { accent: a.theme.accentInk },
  });
}

export type PresentSelectionArgs = {
  theme: TallyTheme;
  isDark: boolean;
  title: string;
  emptyHint?: string;
  rows: SelectionRow[];
  /** lines already ticked — e.g. the row a long-press started from */
  selected?: string[];
};

export function presentSelectionSheet(a: PresentSelectionArgs): Promise<SelectionResult> {
  return presentSelection({
    title: a.title,
    emptyHint: a.emptyHint ?? 'Tap lines to add them up',
    rows: a.rows,
    selected: a.selected ?? [],
    isDark: a.isDark,
    colors: { accent: a.theme.accentInk },
  });
}
