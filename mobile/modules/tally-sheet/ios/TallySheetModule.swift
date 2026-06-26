import ExpoModulesCore
import SwiftUI
import UIKit

// TallySheet — presents the "name + tags" sheet as a floating, rounded card that
// sits inset from the screen edges and lifts above the keyboard (à la Craft's
// "Add tags" / "New tag" dialogs), rather than an edge-to-edge bottom sheet. The
// form is authored entirely in SwiftUI; JS calls `present(options)` and awaits a
// result. The card owns its own editing state and only reports back on Save (or
// "cancel" when the user taps the scrim / ✕). This keeps text entry off the JS
// bridge entirely.

// MARK: - Options (decoded from JS)

struct SheetColors: Record {
  @Field var accent: String = "#b3476a"
  @Field var accent2: String = "#f4dbe2"
  @Field var accentInk: String = "#9c3458"
  @Field var screen: String = "#ececef"
  @Field var card: String = "#ffffff"
  @Field var ink: String = "#1a1a1d"
  @Field var ink2: String = "#6b6b73"
  @Field var ink3: String = "#a6a6af"
  @Field var line: String = "#e4e4ea"
  @Field var deep: String = "#1b1b1e"
  @Field var deepInk: String = "#f4f4f6"
}

struct SheetOptions: Record {
  @Field var title: String = ""
  @Field var subtitle: String = ""
  @Field var showName: Bool = true
  @Field var name: String = ""
  @Field var namePlaceholder: String = ""
  @Field var catalog: [String] = []
  @Field var selected: [String] = []
  @Field var primaryLabel: String = "Save"
  @Field var canSave: Bool = true
  @Field var isDark: Bool = false
  @Field var colors: SheetColors = SheetColors()
}

// MARK: - Module

public class TallySheetModule: Module {
  // Keep presented resolvers alive for the lifetime of their sheet.
  private var live: [SheetResolver] = []

  public func definition() -> ModuleDefinition {
    Name("TallySheet")

    AsyncFunction("present") { (options: SheetOptions, promise: Promise) in
      DispatchQueue.main.async {
        guard let presenter = self.appContext?.utilities?.currentViewController() else {
          promise.resolve(["action": "cancel", "name": options.name, "tags": options.selected])
          return
        }

        let resolver = SheetResolver(promise: promise, name: options.name, tags: options.selected)
        self.live.append(resolver)
        resolver.onRelease = { [weak self] r in self?.live.removeAll { $0 === r } }

        let root = TallySheetView(options: options) { action, name, tags in
          resolver.finish(action: action, name: name, tags: tags)
        }
        .preferredColorScheme(options.isDark ? .dark : .light)

        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.clipsToBounds = false
        if #available(iOS 16.0, *) {
          // Let the card hug its SwiftUI content height.
          host.sizingOptions = [.preferredContentSize]
        }
        host.modalPresentationStyle = .custom
        host.transitioningDelegate = resolver
        resolver.host = host

        presenter.present(host, animated: true)
      }
    }
  }
}

// MARK: - Result plumbing

// Bridges the SwiftUI form / scrim-dismiss back to the JS promise, exactly once.
// Also acts as the transitioning delegate that installs the floating card
// presentation + slide-up animation.
final class SheetResolver: NSObject {
  private let promise: Promise
  private let fallbackName: String
  private let fallbackTags: [String]
  private var done = false
  weak var host: UIViewController?
  var onRelease: ((SheetResolver) -> Void)?

  init(promise: Promise, name: String, tags: [String]) {
    self.promise = promise
    self.fallbackName = name
    self.fallbackTags = tags
  }

  // Called from the form's Save / ✕ buttons.
  func finish(action: String, name: String, tags: [String]) {
    guard !done else { return }
    done = true
    promise.resolve(["action": action, "name": name, "tags": tags])
    host?.dismiss(animated: true)
    onRelease?(self)
  }

  // Called when the user taps the dimmed scrim — discard edits.
  func cancel() {
    guard !done else { return }
    done = true
    promise.resolve(["action": "cancel", "name": fallbackName, "tags": fallbackTags])
    host?.dismiss(animated: true)
    onRelease?(self)
  }
}

extension SheetResolver: UIViewControllerTransitioningDelegate {
  func presentationController(
    forPresented presented: UIViewController,
    presenting: UIViewController?,
    source: UIViewController
  ) -> UIPresentationController? {
    let pc = FloatingCardPresentationController(presentedViewController: presented, presenting: presenting)
    pc.onScrimTap = { [weak self] in self?.cancel() }
    return pc
  }

  func animationController(
    forPresented presented: UIViewController,
    presenting: UIViewController,
    source: UIViewController
  ) -> UIViewControllerAnimatedTransitioning? {
    FloatingCardAnimator(isPresenting: true)
  }

  func animationController(
    forDismissed dismissed: UIViewController
  ) -> UIViewControllerAnimatedTransitioning? {
    FloatingCardAnimator(isPresenting: false)
  }
}

// MARK: - Floating card presentation

// Positions the presented view as a rounded card inset from the sides and bottom,
// over a tap-to-dismiss dimming view, and keeps it floating just above the
// keyboard. Corners are clipped in SwiftUI; the matching drop shadow lives on the
// presented view's layer so it animates with the card.
final class FloatingCardPresentationController: UIPresentationController {
  var onScrimTap: (() -> Void)?

  private let side: CGFloat = 14
  private let corner: CGFloat = 22
  private let restGap: CGFloat = 12 // breathing room above the home indicator
  private let keyboardGap: CGFloat = 24 // a touch more so it clears the keyboard
  private var keyboardHeight: CGFloat = 0

  private lazy var dimming: UIView = {
    let v = UIView()
    v.backgroundColor = UIColor(red: 20 / 255, green: 12 / 255, blue: 8 / 255, alpha: 0.34)
    v.alpha = 0
    v.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(scrimTapped)))
    return v
  }()

  override init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
    super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
    let nc = NotificationCenter.default
    nc.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    nc.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func scrimTapped() { onScrimTap?() }

  override var frameOfPresentedViewInContainerView: CGRect {
    guard let cv = containerView else { return .zero }
    let b = cv.bounds
    let safe = cv.safeAreaInsets
    let width = b.width - side * 2
    let preferred = presentedViewController.preferredContentSize.height
    let estimate = preferred > 1 ? preferred : 360
    let topLimit = safe.top + 24
    let bottom = keyboardHeight > 0 ? keyboardHeight + keyboardGap : max(safe.bottom, 8) + restGap
    let maxHeight = max(140, b.height - topLimit - bottom)
    let height = min(estimate, maxHeight)
    let y = b.height - bottom - height
    return CGRect(x: side, y: y, width: width, height: height)
  }

  override func presentationTransitionWillBegin() {
    guard let cv = containerView else { return }
    dimming.frame = cv.bounds
    dimming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cv.insertSubview(dimming, at: 0)

    if let pv = presentedView {
      pv.clipsToBounds = false
      pv.layer.shadowColor = UIColor(red: 40 / 255, green: 20 / 255, blue: 10 / 255, alpha: 1).cgColor
      pv.layer.shadowOpacity = 0.28
      pv.layer.shadowRadius = 30
      pv.layer.shadowOffset = CGSize(width: 0, height: 18)
    }

    presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
      self.dimming.alpha = 1
    })
  }

  override func dismissalTransitionWillBegin() {
    presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
      self.dimming.alpha = 0
    })
  }

  override func containerViewWillLayoutSubviews() {
    guard let pv = presentedView else { return }
    pv.frame = frameOfPresentedViewInContainerView
    pv.layer.shadowPath = UIBezierPath(roundedRect: pv.bounds, cornerRadius: corner).cgPath
    dimming.frame = containerView?.bounds ?? dimming.frame
  }

  // The SwiftUI content height changes (a tag wraps to a new row, the name field
  // appears) — animate the card to its new size.
  override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
    super.preferredContentSizeDidChange(forChildContentContainer: container)
    relayout(duration: 0.28)
  }

  @objc private func keyboardChanged(_ note: Notification) {
    guard let cv = containerView,
          let info = note.userInfo,
          let endValue = info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
    let isHide = note.name == UIResponder.keyboardWillHideNotification
    let endInContainer = cv.convert(endValue.cgRectValue, from: cv.window)
    keyboardHeight = isHide ? 0 : max(0, cv.bounds.height - endInContainer.minY)
    let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
    relayout(duration: duration)
  }

  private func relayout(duration: TimeInterval) {
    guard let cv = containerView, let pv = presentedView else { return }
    UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut]) {
      pv.frame = self.frameOfPresentedViewInContainerView
      pv.layer.shadowPath = UIBezierPath(roundedRect: pv.bounds, cornerRadius: self.corner).cgPath
      cv.layoutIfNeeded()
    }
  }
}

// MARK: - Slide-up animation

final class FloatingCardAnimator: NSObject, UIViewControllerAnimatedTransitioning {
  let isPresenting: Bool
  init(isPresenting: Bool) { self.isPresenting = isPresenting }

  func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval {
    isPresenting ? 0.34 : 0.24
  }

  func animateTransition(using ctx: UIViewControllerContextTransitioning) {
    let container = ctx.containerView

    if isPresenting {
      guard let toVC = ctx.viewController(forKey: .to),
            let card = ctx.view(forKey: .to) else { ctx.completeTransition(false); return }
      card.frame = ctx.finalFrame(for: toVC)
      card.transform = CGAffineTransform(translationX: 0, y: 26)
      card.alpha = 0
      container.addSubview(card)
      UIView.animate(
        withDuration: transitionDuration(using: ctx),
        delay: 0,
        usingSpringWithDamping: 0.9,
        initialSpringVelocity: 0,
        options: [.curveEaseOut]
      ) {
        card.transform = .identity
        card.alpha = 1
      } completion: { _ in
        ctx.completeTransition(!ctx.transitionWasCancelled)
      }
    } else {
      guard let card = ctx.view(forKey: .from) else { ctx.completeTransition(false); return }
      UIView.animate(
        withDuration: transitionDuration(using: ctx),
        delay: 0,
        options: [.curveEaseIn]
      ) {
        card.transform = CGAffineTransform(translationX: 0, y: 26)
        card.alpha = 0
      } completion: { _ in
        card.transform = .identity
        ctx.completeTransition(!ctx.transitionWasCancelled)
      }
    }
  }
}

// MARK: - SwiftUI form

struct TallySheetView: View {
  let options: SheetOptions
  let onDone: (_ action: String, _ name: String, _ tags: [String]) -> Void

  @State private var name: String
  @State private var catalog: [String]
  @State private var selected: Set<String>
  @State private var adding = false
  @State private var draft = ""
  @FocusState private var nameFocused: Bool
  @FocusState private var newTagFocused: Bool

  init(options: SheetOptions, onDone: @escaping (String, String, [String]) -> Void) {
    self.options = options
    self.onDone = onDone
    _name = State(initialValue: options.name)
    _catalog = State(initialValue: options.catalog)
    _selected = State(initialValue: Set(options.selected))
  }

  private var c: SheetColors { options.colors }

  // Selected tags, returned in catalog order so the result is stable.
  private var orderedSelection: [String] {
    catalog.filter { selected.contains($0) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Title + close, like Craft's dialog header.
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(options.title)
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(Color(hex: c.ink))
          Text(options.subtitle)
            .font(.system(size: 13))
            .foregroundColor(Color(hex: c.ink2))
        }
        Spacer(minLength: 0)
        Button { onDone("cancel", name, orderedSelection) } label: {
          Image(systemName: "xmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(Color(hex: c.ink2))
            .frame(width: 30, height: 30)
            .background(Color(hex: c.card))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }

      if options.showName {
        TextField(options.namePlaceholder, text: $name)
          .font(.system(size: 19, weight: .semibold))
          .foregroundColor(Color(hex: c.ink))
          .focused($nameFocused)
          .submitLabel(.done)
          .onSubmit { if options.canSave { commit() } }
          .padding(.vertical, 12)
          .padding(.horizontal, 14)
          .background(Color(hex: c.card))
          .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(hex: c.line), lineWidth: 1))
          .clipShape(RoundedRectangle(cornerRadius: 13))
          .padding(.top, 16)
      }

      Text("Tags")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(Color(hex: c.ink3))
        .padding(.top, options.showName ? 18 : 16)
        .padding(.bottom, 10)

      FlowLayout(spacing: 8) {
        ForEach(catalog, id: \.self) { tag in
          chip(tag)
        }
        if adding {
          newTagField
        } else {
          newTagButton
        }
      }

      Button(action: commit) {
        Text(options.primaryLabel)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(Color(hex: options.canSave ? c.deepInk : c.ink3))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(Color(hex: options.canSave ? c.deep : c.line))
          .clipShape(RoundedRectangle(cornerRadius: 14))
      }
      .disabled(!options.canSave)
      .padding(.top, 20)
    }
    .padding(.horizontal, 20)
    .padding(.top, 18)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(hex: c.screen))
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .onAppear {
      if options.showName {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { nameFocused = true }
      }
    }
  }

  // A single toggle chip — soft accent by default, solid accent when selected.
  private func chip(_ tag: String) -> some View {
    let on = selected.contains(tag)
    return Button {
      if on { selected.remove(tag) } else { selected.insert(tag) }
    } label: {
      HStack(spacing: 5) {
        if on {
          Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
        }
        Text(tag)
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(on ? .white : Color(hex: c.accentInk))
      }
      .padding(.vertical, 5)
      .padding(.horizontal, 11)
      .background(on ? Color(hex: c.accent) : Color(hex: c.accent2))
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private var newTagButton: some View {
    Button {
      adding = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { newTagFocused = true }
    } label: {
      Text("+ New")
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundColor(Color(hex: c.ink2))
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundColor(Color(hex: c.ink3)))
    }
    .buttonStyle(.plain)
  }

  private var newTagField: some View {
    TextField("new tag…", text: $draft)
      .font(.system(size: 12.5, weight: .semibold))
      .foregroundColor(Color(hex: c.ink))
      .focused($newTagFocused)
      .autocorrectionDisabled()
      .textInputAutocapitalization(.words)
      .submitLabel(.done)
      .onSubmit { addDraftTag() }
      .frame(width: 108)
      .padding(.vertical, 5)
      .padding(.horizontal, 12)
      .background(Color(hex: c.card))
      .overlay(Capsule().stroke(Color(hex: c.accent), lineWidth: 1))
      .clipShape(Capsule())
  }

  private func addDraftTag() {
    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    adding = false
    draft = ""
    guard !trimmed.isEmpty else { return }
    if let existing = catalog.first(where: { $0.lowercased() == trimmed.lowercased() }) {
      selected.insert(existing)
    } else {
      catalog.append(trimmed)
      selected.insert(trimmed)
    }
  }

  private func commit() {
    guard options.canSave else { return }
    onDone("save", name, orderedSelection)
  }
}

// MARK: - Flow layout (wrapping chips)

struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var widest: CGFloat = 0

    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > 0, x + size.width > maxWidth {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
      widest = max(widest, x - spacing)
    }
    let totalWidth = maxWidth == .infinity ? widest : maxWidth
    return CGSize(width: totalWidth, height: y + rowHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let maxWidth = bounds.width
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0

    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > 0, x + size.width > maxWidth {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      view.place(
        at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
        proposal: ProposedViewSize(size)
      )
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}

// MARK: - Hex colour

extension Color {
  init(hex: String) {
    var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if hex.hasPrefix("#") { hex.removeFirst() }
    if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
    var value: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&value)
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
  }
}
