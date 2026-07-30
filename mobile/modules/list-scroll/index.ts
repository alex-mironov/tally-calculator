// list-scroll — scroll the SwiftUI List behind an @expo/ui Host to its end.
//
// Exists because a freshly committed entry lands below the fold on longer tabs
// and SwiftUI offers no bridge-reachable way to scroll a `List` (see the Swift
// side for the full story). Pass the react tag of a plain RN wrapper view
// around the Host; the native side finds the backing UIScrollView underneath
// it and animates to the bottom. iOS-only; a no-op everywhere else.
import { requireOptionalNativeModule } from 'expo';

type ListScrollNativeModule = {
  scrollToEnd(viewTag: number, animated: boolean): Promise<void>;
};

const native = requireOptionalNativeModule<ListScrollNativeModule>('ListScroll');

/** True when the native module is linked (an iOS dev/release build). */
export const isListScrollAvailable = native != null;

/** Scroll the list under the tagged view to its end. Safe to call blind. */
export function scrollListToEnd(viewTag: number | null, animated = true): void {
  if (viewTag == null) return;
  native?.scrollToEnd(viewTag, animated);
}
