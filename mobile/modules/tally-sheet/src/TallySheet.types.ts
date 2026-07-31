/**
 * Theme colours handed to the native sheet (hex strings). The sheet is a
 * standard grouped form drawn by the system, so the accent — the tint its
 * controls take — is the only colour the app still owns.
 */
export type SheetColors = {
  accent: string;
};

/** Everything the native sheet needs to render and report back. */
export type SheetOptions = {
  title: string;
  subtitle: string;
  /** show the name field (Save tab) or tags only (Edit tags) */
  showName: boolean;
  name: string;
  namePlaceholder: string;
  catalog: string[];
  selected: string[];
  primaryLabel: string;
  /** gate the primary button (e.g. nothing to save yet) */
  canSave: boolean;
  isDark: boolean;
  colors: SheetColors;
};

/** What the sheet hands back. `tags` may contain names not yet in the catalog. */
export type SheetResult = {
  action: 'save' | 'cancel';
  name: string;
  tags: string[];
};
