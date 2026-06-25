import ExpoModulesCore
import SwiftUI
import UIKit

// TallySheet — presents the "name + tags" sheet as a genuine native iOS sheet
// (UISheetPresentationController with detents + grabber), with the form authored
// entirely in SwiftUI. JS calls `present(options)` and awaits a result; the sheet
// owns its own editing state and only reports back on Save (or "cancel" when the
// user swipes it away). This keeps text entry off the JS bridge entirely.

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
        host.view.backgroundColor = UIColor(Color(hex: options.colors.screen))
        resolver.host = host

        if let sheet = host.sheetPresentationController {
          sheet.detents = [.medium(), .large()]
          sheet.prefersGrabberVisible = true
          sheet.preferredCornerRadius = 22
          sheet.largestUndimmedDetentIdentifier = nil
        }
        host.presentationController?.delegate = resolver

        presenter.present(host, animated: true)
      }
    }
  }
}

// MARK: - Result plumbing

// Bridges the SwiftUI form / swipe-dismiss back to the JS promise, exactly once.
final class SheetResolver: NSObject, UIAdaptivePresentationControllerDelegate {
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

  // Called from the form's Save button (and any explicit dismiss).
  func finish(action: String, name: String, tags: [String]) {
    guard !done else { return }
    done = true
    promise.resolve(["action": action, "name": name, "tags": tags])
    host?.dismiss(animated: true)
    onRelease?(self)
  }

  // Called when the user swipes the sheet down.
  func presentationControllerDidDismiss(_ controller: UIPresentationController) {
    guard !done else { return }
    done = true
    promise.resolve(["action": "cancel", "name": fallbackName, "tags": fallbackTags])
    onRelease?(self)
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
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text(options.title)
          .font(.system(size: 22, weight: .semibold))
          .foregroundColor(Color(hex: c.ink))
        Text(options.subtitle)
          .font(.system(size: 13))
          .foregroundColor(Color(hex: c.ink2))
          .padding(.top, 3)

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
    }
    .background(Color(hex: c.screen))
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
