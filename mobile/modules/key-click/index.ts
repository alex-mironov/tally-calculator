// key-click — the standard iOS keyboard "tock" for Tally's custom keypad.
//
// HIG "Virtual keyboards" asks custom input views to play the system keyboard
// sound so taps feel like taps anywhere else. The native side routes through
// UIDevice.playInputClick(), which stays silent when the user has turned
// keyboard clicks off in Settings ▸ Sounds & Haptics — so there is deliberately
// no volume or enable flag here. iOS-only; a no-op everywhere else.
import { requireOptionalNativeModule } from 'expo';

type KeyClickNativeModule = { play(): void };

const native = requireOptionalNativeModule<KeyClickNativeModule>('KeyClick');

/** True when the native module is linked (an iOS dev/release build). */
export const isKeyClickAvailable = native != null;

/** Play one keyboard click, if the user has keyboard sounds switched on. */
export function playKeyClick(): void {
  native?.play();
}
