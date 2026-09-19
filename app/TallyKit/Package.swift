// swift-tools-version: 6.2
import PackageDescription

// TallyKit — everything Tally knows how to do, with no UI attached: the
// expression engine, the Entry/Tab model, the reference pipeline, the store and
// its persistence. The app target is a thin SwiftUI layer over this.
//
// It is a package rather than a folder in the app target so `swift test` runs
// the engine's golden fixture from the command line, without a simulator.
let package = Package(
  name: "TallyKit",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "TallyKit", targets: ["TallyKit"])
  ],
  targets: [
    .target(name: "TallyKit"),
    .testTarget(
      name: "TallyKitTests",
      dependencies: ["TallyKit"],
      resources: [.copy("Fixtures")]
    ),
  ]
)
