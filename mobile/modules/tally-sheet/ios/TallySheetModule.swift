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
