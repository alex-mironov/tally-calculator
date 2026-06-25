/** Theme colours handed to the native sheet (hex strings). */
export type SheetColors = {
  accent: string;
  accent2: string;
  accentInk: string;
  screen: string;
  card: string;
  ink: string;
  ink2: string;
  ink3: string;
  line: string;
  deep: string;
  deepInk: string;
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
