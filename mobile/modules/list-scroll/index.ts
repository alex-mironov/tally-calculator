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
  hideTopEdgeEffect(viewTag: number): Promise<boolean>;
};

const native = requireOptionalNativeModule<ListScrollNativeModule>('ListScroll');

/** True when the native module is linked (an iOS dev/release build). */
export const isListScrollAvailable = native != null;

/** Scroll the list under the tagged view to its end. Safe to call blind. */
export function scrollListToEnd(viewTag: number | null, animated = true): void {
  if (viewTag == null) return;
  native?.scrollToEnd(viewTag, animated);
}

/**
 * Switch off iOS 26's scroll-edge blur along the top of the list under the
 * tagged view (see the Swift side for why). SwiftUI mounts the List a beat
 * after the RN wrapper lays out, so this retries a few frames until the
 * backing scroll view exists. Safe to call blind; a no-op before iOS 26.
 */
export function hideListTopEdgeEffect(viewTag: number | null, attempts = 6): void {
  if (viewTag == null || native?.hideTopEdgeEffect == null) return;
  void native.hideTopEdgeEffect(viewTag).then((found) => {
    if (!found && attempts > 1) setTimeout(() => hideListTopEdgeEffect(viewTag, attempts - 1), 50);
  });
}
