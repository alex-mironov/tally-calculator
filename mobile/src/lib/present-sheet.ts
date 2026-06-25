// present-sheet.ts — thin JS wrapper over the native `TallySheet` SwiftUI module
// (modules/tally-sheet). Maps the live theme onto the colours the native form
// expects and presents the "name + tags" sheet, resolving with the user's
// choice. On platforms without the native module it resolves to a no-op cancel.
import { presentSheet, type SheetResult } from '../../modules/tally-sheet';
import type { TallyTheme } from '@/constants/tally-theme';

export type { SheetResult };

function sheetColors(t: TallyTheme) {
  return {
    accent: t.accent,
    accent2: t.accent2,
    accentInk: t.accentInk,
    screen: t.screen,
    card: t.card,
    ink: t.ink,
    ink2: t.ink2,
    ink3: t.ink3,
    line: t.line,
    deep: t.deep,
    deepInk: t.deepInk,
  };
}

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
    colors: sheetColors(a.theme),
  });
}
