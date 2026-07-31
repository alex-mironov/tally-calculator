// present-sheet.ts — thin JS wrapper over the native `TallySheet` SwiftUI module
// (modules/tally-sheet). Presents the "name + tags" sheet and resolves with the
// user's choice. On platforms without the native module it resolves to a no-op
// cancel.
//
// The sheet is a system-drawn grouped form, so the theme barely crosses over:
// the accent tints its controls and the mode picks the colour scheme. Everything
// else is the platform's.
import { presentSheet, type SheetResult } from '../../modules/tally-sheet';
import type { TallyTheme } from '@/constants/tally-theme';

export type { SheetResult };

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
    colors: { accent: a.theme.accent },
  });
}
