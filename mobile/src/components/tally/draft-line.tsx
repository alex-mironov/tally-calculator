// draft-line.tsx — the entry card's one-line draft: the sum being typed, on a
// single line that never wraps and never hides the digits being typed.
//
// The line is right-anchored. The tail — the part that changes on every key —
// stays put against the card's trailing edge, and a sum longer than the card
// runs off the *leading* edge instead, under a short fade so the cut reads as
// "there's more" rather than as a clipped glyph (the design's 36px mask-image).
// The hidden head is a swipe away: the line is a horizontal scroll view, and
// it returns to the tail on its own whenever the draft changes.
//
// Right-anchoring a scroll view without a jump on every keystroke is the
// inverted-list trick: the scroll view is mirrored (scaleX −1) and its content
// mirrored back, so offset 0 *is* the tail, and content that grows pushes the
// head further off the leading edge instead of moving the tail. The fade is a
// real mask (MaskedView), so the text goes transparent over the glass rather
// than being painted over with a colour the glass wouldn't match — and it
// lifts off as you scroll back to the head, so the first digit is never dimmed
// when nothing is hidden behind it.
//
// The line handles its own tap (`onPress`) instead of sitting inside the
// card's: on the new architecture a scroll view won't scroll while an ancestor
// view holds the JS responder, and a Pressable wrapped around this one took it
// on every touch-down — the line couldn't be dragged at all. A Pressable
// *inside* the scroll view is the ordinary case and gets cancelled by the
// drag like any list row.
import MaskedView from '@react-native-masked-view/masked-view';
import { LinearGradient } from 'expo-linear-gradient';
import { useRef, type ReactNode } from 'react';
import { Pressable, StyleSheet, View, type LayoutChangeEvent } from 'react-native';
import Animated, {
  Extrapolation,
  interpolate,
  useAnimatedRef,
  useAnimatedScrollHandler,
  useAnimatedStyle,
  useSharedValue,
} from 'react-native-reanimated';

/** Fixed, so the card never changes height as the draft grows or steps down. */
export const DRAFT_LINE_HEIGHT = 44;
/** design: `mask-image: linear-gradient(to right, transparent, #000 36px)` */
const FADE = 36;

type Props = {
  children: ReactNode;
  /** a tap on the line itself — the card's "bring the keypad back" */
  onPress?: () => void;
};

export function DraftLine({ children, onPress }: Props) {
  const scroll = useAnimatedRef<Animated.ScrollView>();
  // how much of the head is off the leading edge while the view sits at the
  // tail — the content's width past the viewport's, never below zero
  const overflow = useSharedValue(0);
  // the live scroll offset: 0 at the tail, growing towards the head
  const offset = useSharedValue(0);
  const viewport = useRef(0);
  const content = useRef(0);

  const sync = () => overflow.set(Math.max(0, content.current - viewport.current));
  const onLayout = (e: LayoutChangeEvent) => {
    viewport.current = e.nativeEvent.layout.width;
    sync();
  };
  const onContentSizeChange = (w: number) => {
    content.current = w;
    sync();
    // a keystroke while scrolled back towards the head returns to the tail —
    // that's where the change landed. A no-op when already there.
    scroll.current?.scrollTo({ x: 0, animated: true });
  };
  const onScroll = useAnimatedScrollHandler((e) => offset.set(e.contentOffset.x));

  // The solid cover over the gradient band: opaque (no fade) while nothing is
  // hidden under it, gone once the head has run more than a few points past
  // the edge. `overflow − offset` is exactly how much is still off screen.
  const coverStyle = useAnimatedStyle(() => ({
    opacity: interpolate(overflow.get() - offset.get(), [0, FADE / 2], [1, 0], Extrapolation.CLAMP),
  }));

  // Only alpha matters to a mask: the band ramps from clear to solid over the
  // fade width, and the rest of the line is solid.
  const mask = (
    <View style={styles.mask}>
      <View style={styles.band}>
        <LinearGradient
          colors={['rgba(0,0,0,0)', '#000']}
          start={{ x: 0, y: 0.5 }}
          end={{ x: 1, y: 0.5 }}
          style={StyleSheet.absoluteFill}
        />
        <Animated.View style={[StyleSheet.absoluteFill, styles.solid, coverStyle]} />
      </View>
      <View style={[styles.rest, styles.solid]} />
    </View>
  );

  return (
    <MaskedView style={styles.line} maskElement={mask}>
      <Animated.ScrollView
        ref={scroll}
        horizontal
        style={styles.flip}
        contentContainerStyle={styles.content}
        showsHorizontalScrollIndicator={false}
        // a draft that fits shouldn't rubber-band when brushed
        alwaysBounceHorizontal={false}
        directionalLockEnabled
        // a tap on the line is the card's (it brings a stowed keypad back), and
        // must never dismiss the note field's keyboard on the way through
        keyboardShouldPersistTaps="always"
        onLayout={onLayout}
        onContentSizeChange={onContentSizeChange}
        onScroll={onScroll}
        scrollEventThrottle={16}>
        <Pressable onPress={onPress} disabled={!onPress} style={[styles.row, styles.flip]}>
          {children}
        </Pressable>
      </Animated.ScrollView>
    </MaskedView>
  );
}

const styles = StyleSheet.create({
  line: { height: DRAFT_LINE_HEIGHT },
  flip: { transform: [{ scaleX: -1 }] },
  content: { height: DRAFT_LINE_HEIGHT, alignItems: 'center' },
  // pills and text runs sit on one row, centred on the line
  row: { flexDirection: 'row', alignItems: 'center', columnGap: 4 },

  mask: { flex: 1, flexDirection: 'row' },
  band: { width: FADE },
  rest: { flex: 1 },
  solid: { backgroundColor: '#000' },
});
