// tally-sheet — JS surface for the native SwiftUI "name + tags" sheet.
//
// iOS-only. We load it optionally so the same import resolves on Android/web (and
// on a JS-only/Expo Go run): there `present` falls back to a "cancel" result that
// leaves the caller's state untouched. Callers should treat the absence of the
// native module as "use the JS fallback sheet" if they keep one around.
import { requireOptionalNativeModule } from 'expo';

import type { TallySheetModule } from './src/TallySheetModule';
import type { SheetOptions, SheetResult } from './src/TallySheet.types';

export type { SheetColors, SheetOptions, SheetResult } from './src/TallySheet.types';

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
