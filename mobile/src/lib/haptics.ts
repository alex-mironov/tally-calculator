// haptics.ts — Tally's haptic vocabulary. One name per meaning so every screen
// speaks the same tactile language, tiered by significance:
//   tap     · light tick for small touches — keypad keys, opening a saved tab
//   select  · choosing or toggling — tag chips, accent swatches, picking a row
//   impact  · significant physical change — deletes, clearing the tab, long-press menus
//   success · an operation completed — entry committed, tab saved
//   error   · an operation rejected — invalid expression
import * as Haptics from 'expo-haptics';

export const tap = () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
export const select = () => Haptics.selectionAsync();
export const impact = () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
export const success = () => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
export const error = () => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
