import ExpoModulesCore
import SwiftUI
import UIKit

// TallySheet — the "name + tags" sheet, presented as a genuine system sheet.
// JS calls `present(options)` and awaits a result; the form is authored entirely
// in SwiftUI and owns its own editing state, so text entry never touches the JS
// bridge. Only the outcome crosses back: "save" with the final name and tags, or
// "cancel" when the user backs out.
//
// Everything about the presentation is the system's (HIG "Sheets"): detents the
// user can drag between, a grabber, swipe-to-dismiss, keyboard avoidance, the
// dimmed parent, the corner radius. The body is a standard grouped `Form` inside
// a `NavigationStack`, so Cancel sits on the leading edge of the sheet's toolbar
// and the confirming action on the trailing edge, exactly where iOS puts them.
// Confirming before unsaved edits are thrown away is the one thing HIG asks an
// app to add on top of the system behaviour.

// MARK: - Options (decoded from JS)

// The form is system-drawn, so the only colour it needs is the app's accent —
// everything else comes from the platform.
struct SheetColors: Record {
  @Field var accent: String = "#b3476a"
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

/// One line of the tab, flattened for display — the sheet does no maths on the
/// expression, it just shows what JS already rendered.
struct SelectionRow: Record {
  @Field var id: String = ""
  /// the line's note, or a stand-in like "No note"
  @Field var title: String = ""
  /// the sticky line number, shown small next to the title
  @Field var number: String = ""
  /// the expression under the title, already resolved to names ("65× Rate")
  @Field var detail: String = ""
  /// the formatted amount on the trailing edge
  @Field var amount: String = ""
  /// the raw value, so the sheet can subtotal what's ticked
  @Field var value: Double = 0
}

struct SelectionOptions: Record {
  @Field var title: String = "Select lines"
  /// footer hint shown while nothing is ticked
  @Field var emptyHint: String = "Tap lines to add them up"
  @Field var rows: [SelectionRow] = []
  @Field var selected: [String] = []
  @Field var isDark: Bool = false
  @Field var colors: SheetColors = SheetColors()
}

// MARK: - Module

public class TallySheetModule: Module {
  // Keep presented resolvers alive for the lifetime of their sheet.
  private var live: [SheetResolver] = []
  private var liveSelections: [SelectionResolver] = []

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

        let model = SheetModel(options: options)
        resolver.model = model

        let root = TallySheetView(options: options, model: model) { action, name, tags in
          resolver.finish(action: action, name: name, tags: tags)
        }

        let host = UIHostingController(rootView: root)
        // The app carries its own light/dark switch, independent of the system's.
        // It has to be set on the controller, not as `preferredColorScheme` on the
        // view: the sheet's own chrome — the form background, the nav bar, the
        // confirmation popover — is drawn by UIKit from the trait collection, and
        // a SwiftUI-level preference never reaches it.
        host.overrideUserInterfaceStyle = options.isDark ? .dark : .light
        // …and the sheet's own backdrop has to be painted opaque on top of that.
        // The default is translucent and samples the presenting controller, which
        // is on the *system* appearance — so on a light phone running the app in
        // dark, the form's white-on-glass text sat over a light backdrop.
        host.view.backgroundColor = .systemGroupedBackground
        host.modalPresentationStyle = .pageSheet
        // HIG "Sheets": support the medium detent for progressive disclosure, and
        // include a grabber so the sheet advertises that it resizes — the grabber
        // is also how VoiceOver users move between detents.
        if let sheet = host.sheetPresentationController {
          sheet.detents = [.medium(), .large()]
          sheet.selectedDetentIdentifier = .medium
          sheet.prefersGrabberVisible = true
          sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        // The resolver vetoes a swipe-dismiss that would discard edits, and
        // answers for the sheet going away behind our back.
        host.presentationController?.delegate = resolver
        resolver.host = host

        presenter.present(host, animated: true)
      }
    }

    // "What do these three come to?" — a question the running total can't
    // answer. A read-only lens over the tab: tick lines, watch the subtotal,
    // dismiss. Nothing is committed, so it resolves with the final selection
    // purely so the caller can act on it later if it ever wants to.
    AsyncFunction("presentSelection") { (options: SelectionOptions, promise: Promise) in
      DispatchQueue.main.async {
        guard let presenter = self.appContext?.utilities?.currentViewController() else {
          promise.resolve(["selected": options.selected])
          return
        }

        let resolver = SelectionResolver(promise: promise)
        self.liveSelections.append(resolver)
        resolver.onRelease = { [weak self] r in self?.liveSelections.removeAll { $0 === r } }

        let root = SelectionSheetView(options: options) { picked in
          resolver.finish(selected: picked)
        }

        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = options.isDark ? .dark : .light
        host.view.backgroundColor = .systemGroupedBackground
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
          // Opens tall — the whole point is seeing the lines — but it still
          // pulls down to medium so the tab underneath stays glanceable.
          sheet.detents = [.medium(), .large()]
          sheet.selectedDetentIdentifier = .large
          sheet.prefersGrabberVisible = true
          sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        host.presentationController?.delegate = resolver
        resolver.host = host

        presenter.present(host, animated: true)
      }
    }
  }
}

// MARK: - Form state

// The sheet's editing state, held outside the SwiftUI view so the presentation
// controller can ask whether a swipe-dismiss would throw anything away.
final class SheetModel: ObservableObject {
  @Published var name: String
  @Published var catalog: [String]
  @Published var selected: Set<String>
  @Published var adding = false
  @Published var draft = ""
  /// Raised by the presentation controller when a swipe would discard edits.
  @Published var confirmingDiscard = false

  private let initialName: String
  private let initialSelection: Set<String>

  init(options: SheetOptions) {
    name = options.name
    catalog = options.catalog
    selected = Set(options.selected)
    initialName = options.name
    initialSelection = Set(options.selected)
  }

  /// Anything the user would lose by backing out.
  var isDirty: Bool { name != initialName || selected != initialSelection }

  /// Selected tags in catalog order, so the result is stable across edits.
  var orderedSelection: [String] { catalog.filter { selected.contains($0) } }

  func toggle(_ tag: String) {
    if selected.contains(tag) {
      selected.remove(tag)
    } else {
      selected.insert(tag)
    }
  }

  /// Commit the inline "new tag" field. A name that already exists just selects
  /// the tag it matches rather than making a near-duplicate.
  func commitDraftTag() {
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
}

// MARK: - Result plumbing

// Bridges the form's Cancel / Save — and a swipe-dismiss — back to the JS
// promise, exactly once.
final class SheetResolver: NSObject {
  private let promise: Promise
  private let fallbackName: String
  private let fallbackTags: [String]
  private var done = false
  weak var host: UIViewController?
  var model: SheetModel?
  var onRelease: ((SheetResolver) -> Void)?

  init(promise: Promise, name: String, tags: [String]) {
    self.promise = promise
    self.fallbackName = name
    self.fallbackTags = tags
  }

  // Called from the form's toolbar buttons and the discard confirmation.
  func finish(action: String, name: String, tags: [String]) {
    guard !done else { return }
    done = true
    promise.resolve(["action": action, "name": name, "tags": tags])
    host?.dismiss(animated: true)
    onRelease?(self)
  }

  // The sheet is already gone (the user swiped it away) — resolve, don't dismiss.
  private func resolveDismissed() {
    guard !done else { return }
    done = true
    promise.resolve(["action": "cancel", "name": fallbackName, "tags": fallbackTags])
    onRelease?(self)
  }
}

extension SheetResolver: UIAdaptivePresentationControllerDelegate {
  // HIG "Sheets": support swiping to dismiss, but confirm first when that would
  // discard unsaved changes. Vetoing the swipe is what makes iOS ask us.
  func presentationControllerShouldDismiss(_ controller: UIPresentationController) -> Bool {
    !(model?.isDirty ?? false)
  }

  func presentationControllerDidAttemptToDismiss(_ controller: UIPresentationController) {
    model?.confirmingDiscard = true
  }

  func presentationControllerDidDismiss(_ controller: UIPresentationController) {
    resolveDismissed()
  }
}

// MARK: - SwiftUI form

struct TallySheetView: View {
  let options: SheetOptions
  @ObservedObject var model: SheetModel
  let onDone: (_ action: String, _ name: String, _ tags: [String]) -> Void

  private enum Field: Hashable { case name, newTag }
  @FocusState private var focus: Field?

  var body: some View {
    NavigationStack {
      // The grouped background is painted here rather than left to the Form.
      // A sheet's default backdrop is translucent and samples the screen behind
      // it, and the screen behind is on the *system* appearance — so with the
      // app in dark on a light phone, white form text sat over a light backdrop.
      ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        form
      }
      .navigationTitle(options.title)
      .navigationBarTitleDisplayMode(.inline)
      // HIG "Sheets" (iOS): Cancel on the leading edge, the confirming action on
      // the trailing edge — and never a Done without a Cancel beside it.
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { discard() }
        }
        ToolbarItem(placement: .confirmationAction) {
          // The sheet's one key action, so it takes the prominent style HIG
          // "Toolbars" reserves for a Done/Submit on the trailing edge.
          Button(options.primaryLabel) { commit() }
            .buttonStyle(.borderedProminent)
            .disabled(!options.canSave)
        }
      }
      .confirmationDialog(
        "Discard your changes?",
        isPresented: $model.confirmingDiscard,
        titleVisibility: .visible
      ) {
        Button("Discard Changes", role: .destructive) { discard() }
        Button("Keep Editing", role: .cancel) {}
      }
    }
    .tint(Color(hex: options.colors.accent))
    .onAppear {
      // The name field is the point of the sheet, so it takes the keyboard —
      // after the presentation animation, which otherwise swallows the focus.
      guard options.showName else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focus = .name }
    }
  }

  private var form: some View {
    Form {
      if options.showName {
        Section {
          TextField(options.namePlaceholder, text: $model.name)
            .focused($focus, equals: .name)
            .submitLabel(.done)
            .onSubmit { commit() }
        } footer: {
          Text(options.subtitle)
        }
        Section("Tags") { tagRows }
      } else {
        Section {
          tagRows
        } header: {
          Text("Tags")
        } footer: {
          Text(options.subtitle)
        }
      }
    }
    // the ZStack behind it owns the background now
    .scrollContentBackground(.hidden)
  }

  // One row per tag: tap anywhere on it to file or unfile the calculation, with
  // a checkmark on the ones that are on. Standard list rows, so they're a full
  // 44pt tall and VoiceOver reads them as selected.
  @ViewBuilder private var tagRows: some View {
    ForEach(model.catalog, id: \.self) { tag in
      let on = model.selected.contains(tag)
      Button {
        model.toggle(tag)
      } label: {
        HStack {
          Text(tag)
          Spacer(minLength: 12)
          if on {
            Image(systemName: "checkmark")
              .fontWeight(.semibold)
              .foregroundStyle(Color(hex: options.colors.accent))
          }
        }
        .contentShape(Rectangle())
      }
      // .plain so the row reads as a list row with a checkmark, not as a row of
      // tinted button text — the tint belongs to the checkmark alone.
      .buttonStyle(.plain)
      .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    if model.adding {
      TextField("New tag", text: $model.draft)
        .focused($focus, equals: .newTag)
        .submitLabel(.done)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.words)
        .onSubmit { model.commitDraftTag() }
    } else {
      Button {
        model.adding = true
        focus = .newTag
      } label: {
        Label("Add Tag", systemImage: "plus")
      }
    }
  }

  private func commit() {
    guard options.canSave else { return }
    onDone("save", model.name, model.orderedSelection)
  }

  private func discard() {
    onDone("cancel", model.name, model.orderedSelection)
  }
}

// MARK: - Selection sheet

// Resolves the selection promise exactly once, whether the user tapped the
// confirm button or swiped the sheet away. Nothing is ever discarded here —
// selecting is a lens, not an edit — so a swipe needs no confirmation.
final class SelectionResolver: NSObject {
  private let promise: Promise
  private var done = false
  weak var host: UIViewController?
  var onRelease: ((SelectionResolver) -> Void)?

  init(promise: Promise) { self.promise = promise }

  func finish(selected: [String]) {
    guard !done else { return }
    done = true
    promise.resolve(["selected": selected])
    host?.dismiss(animated: true)
    onRelease?(self)
  }

  private func resolveDismissed(selected: [String]) {
    guard !done else { return }
    done = true
    promise.resolve(["selected": selected])
    onRelease?(self)
  }
}

extension SelectionResolver: UIAdaptivePresentationControllerDelegate {
  func presentationControllerDidDismiss(_ controller: UIPresentationController) {
    resolveDismissed(selected: [])
  }
}

// A genuine SwiftUI `List`: the card shape, the row insets and the separators
// are all drawn by the system. That is the whole point of this screen being
// native — the previous version hosted React Native views as rows, so their
// heights were measured by RN while the cells were laid out by SwiftUI, and a
// two-line row's highlight drifted out of alignment and overlapped its
// neighbour.
//
// Ticking is ours rather than `List(selection:)` in edit mode. Edit mode's
// multi-select highlight is a full-bleed grey fill painted by UIKit on the
// cell, so in an inset-grouped list it ran out past the card's rounded corners
// to the screen edges. Apple's own edit modes (Mail, Photos) don't fill the row
// at all — the leading circle carries the state — so that's what this does:
// `checkmark.circle` / `circle` on the leading edge, tinted with the accent
// (HIG "Icons" → Standard icons, Selection).
struct SelectionSheetView: View {
  let options: SelectionOptions
  let onDone: (_ selected: [String]) -> Void

  @State private var selection: Set<String>

  init(options: SelectionOptions, onDone: @escaping ([String]) -> Void) {
    self.options = options
    self.onDone = onDone
    _selection = State(initialValue: Set(options.selected))
  }

  private var accent: Color { Color(hex: options.colors.accent) }
  private var picked: [SelectionRow] { options.rows.filter { selection.contains($0.id) } }
  private var subtotal: Double { picked.reduce(0) { $0 + $1.value } }
  private var allPicked: Bool { !options.rows.isEmpty && selection.count == options.rows.count }

  var body: some View {
    NavigationStack {
      List(options.rows, id: \.id) { row in
        let on = selection.contains(row.id)
        Button {
          toggle(row.id)
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            // hidden from VoiceOver: the row already carries .isSelected below,
            // so the state is announced once rather than described twice
            Image(systemName: on ? "checkmark.circle" : "circle")
              .foregroundStyle(on ? accent : Color(uiColor: .tertiaryLabel))
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
              HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(row.title)
                if !row.number.isEmpty {
                  Text(row.number).font(.caption2).foregroundStyle(.tertiary)
                }
              }
              if !row.detail.isEmpty {
                Text(row.detail)
                  .font(.caption)
                  .monospaced()
                  .foregroundStyle(accent)
              }
            }
            Spacer(minLength: 12)
            Text(row.amount).monospacedDigit().foregroundStyle(.secondary)
          }
          // the gaps between the title and the amount stay tappable
          .contentShape(Rectangle())
        }
        // .plain so the row reads as a list row, not as a row of tinted button
        // text — the accent belongs to the circle and the expression alone.
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
      }
      .listStyle(.insetGrouped)
      .navigationTitle(options.title)
      .navigationBarTitleDisplayMode(.inline)
      // HIG "Toolbars": no custom backgrounds on bar items — the bar already
      // gives each one its own container, and a `.bordered`/`.borderedProminent`
      // style on top of that got sized as a fixed circular glass button, which
      // clipped "Deselect All" down to a couple of letters on the leading edge
      // and swelled Done into an accent blob on the trailing one. Plain buttons,
      // then: text rather than symbols, because neither selecting-all nor
      // "I'm finished looking" is well represented by an icon. `.confirmationAction`
      // already draws Done in the bold weight iOS gives the confirming item, so
      // it needs no styling of its own.
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(allPicked ? "Deselect All" : "Select All") {
            selection = allPicked ? [] : Set(options.rows.map(\.id))
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { onDone(picked.map(\.id)) }
        }
      }
      // The answer sits where the running total sits on the tab behind — pinned
      // below the list rather than scrolling with it.
      .safeAreaInset(edge: .bottom) {
        HStack {
          Text(
            selection.isEmpty
              ? options.emptyHint
              : "\(selection.count) of \(options.rows.count) selected"
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
          Spacer(minLength: 12)
          Text(Self.money(subtotal))
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(selection.isEmpty ? .secondary : accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
      }
    }
    .tint(accent)
  }

  private func toggle(_ id: String) {
    if selection.contains(id) {
      selection.remove(id)
    } else {
      selection.insert(id)
    }
  }

  // Matches Calc.fmt on the JS side: grouped thousands, always two decimals.
  // The locale is pinned rather than left to the device, because Calc.fmt hard-
  // codes "," for grouping and "." for the decimal — so on a comma-decimal
  // phone the subtotal here read "42,20" directly under a row reading "42.20".
  // Two separators for the same currency in one sheet; whichever convention the
  // app settles on, both sides have to say it the same way.
  private static func money(_ n: Double) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    // Calc.fmt writes a real minus sign (U+2212), not a hyphen
    f.minusSign = "−"
    return f.string(from: NSNumber(value: n)) ?? String(format: "%.2f", n)
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
