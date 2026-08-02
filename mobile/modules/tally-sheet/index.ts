// tally-sheet — JS surface for the app's native SwiftUI sheets: the "name +
// tags" form, and the multi-select lens over a tab's lines.
//
// iOS-only. We load it optionally so the same import resolves on Android/web (and
// on a JS-only/Expo Go run): there `present` falls back to a "cancel" result that
// leaves the caller's state untouched. Callers should treat the absence of the
// native module as "use the JS fallback sheet" if they keep one around.
import { requireOptionalNativeModule } from 'expo';

import type { TallySheetModule } from './src/TallySheetModule';
import type {
  SelectionOptions,
  SelectionResult,
  SheetOptions,
  SheetResult,
} from './src/TallySheet.types';

export type {
  SelectionOptions,
  SelectionResult,
  SelectionRow,
  SheetColors,
  SheetOptions,
  SheetResult,
} from './src/TallySheet.types';

const native = requireOptionalNativeModule<TallySheetModule>('TallySheet');

/** True when the native sheet module is linked (an iOS dev/release build). */
export const isNativeSheetAvailable = native != null;

/**
 * Present the native sheet and resolve with the user's choice. When the native
 * module isn't available, resolves to a no-op "cancel" carrying the inputs back.
 */
export function presentSheet(options: SheetOptions): Promise<SheetResult> {
  if (!native) {
    return Promise.resolve({ action: 'cancel', name: options.name, tags: options.selected });
  }
  return native.present(options);
}

/**
 * Present the multi-select lens over a tab's lines and resolve with what was
 * ticked when it closed. Selecting commits nothing, so without the native
 * module this is simply a no-op.
 */
export function presentSelection(options: SelectionOptions): Promise<SelectionResult> {
  if (!native) return Promise.resolve({ selected: [] });
  return native.presentSelection(options);
}
