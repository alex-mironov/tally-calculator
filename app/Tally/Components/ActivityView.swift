// ActivityView.swift — the system share sheet.
//
// `ShareLink` wants its item up front, and Tally's share URL doesn't exist
// until the snapshot has been POSTed to the Worker — so the sheet is presented
// once the link comes back, which is what this wraps.
import SwiftUI
import UIKit

struct ActivityView: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A URL that can drive `.sheet(item:)`.
struct SharePayload: Identifiable {
  let url: URL
  var id: String { url.absoluteString }
}
