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

/**
 * One line of the tab, flattened for the selection sheet. The sheet does no
 * maths on the expression — everything here is already display-ready.
 */
export type SelectionRow = {
  id: string;
  /** the note, or a stand-in like "No note" */
  title: string;
  /** sticky line number, e.g. "#4" */
  number: string;
  /** the expression with references resolved to names, e.g. "65× Rate" */
  detail: string;
  /** formatted amount, e.g. "1,204.50" */
  amount: string;
  /** raw value, so the sheet can subtotal what's ticked */
  value: number;
};

export type SelectionOptions = {
  title: string;
  /** footer hint shown while nothing is ticked */
  emptyHint: string;
  rows: SelectionRow[];
  selected: string[];
  isDark: boolean;
  colors: SheetColors;
};

/** What the selection sheet hands back — empty when it was swiped away. */
export type SelectionResult = {
  selected: string[];
};
