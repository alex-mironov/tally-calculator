// haptics.ts — Tally's haptic vocabulary. One name per meaning so every screen
// speaks the same tactile language.
//
// Haptics mark *outcomes*, not touches. A key, a row, a bar button or a menu
// item gives no haptic of its own: the keypad has the system click sound for
// that (the way the system keyboard and Calculator do), and for everything
// else the screen changing under the finger is feedback enough. What's left
// is deliberately sparse and light, so the few that remain still register —
// a tick on every one of twenty keys had turned the phone into a buzzer and
// made the commit, the one moment worth feeling, indistinguishable from it.
//   tap     · light tick — an entry committed, a fresh tab started
//   select  · the selection tick — something toggled on or off: a line in a
//             selection, a tag, an accent swatch, the keypad stowed or brought
//             back
//   impact  · medium knock — something was removed (a line, a saved tab)
//   success · a completed save; the same light tick as `tap`, not the system
//             "success" notification — its two-beat buzz is far too much for
//             an action that happens every few seconds
//   error   · one firm, rigid knock — a commit the engine rejected. Again not
//             the notification pattern: the flash on the card already says
//             "no", the haptic only underlines it
import * as Haptics from 'expo-haptics';

export const tap = () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
export const select = () => Haptics.selectionAsync();
export const impact = () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
export const success = () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
export const error = () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Rigid);
