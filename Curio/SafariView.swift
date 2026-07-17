import SwiftUI
import SafariServices

// MARK: - SafariView
// In-app browser sheet for swipe-right "show me the actual source" — stays
// inside Curio instead of backgrounding it out to system Safari.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor(Color(hex: "#6AA0FF"))
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

// So a plain URL can drive `.sheet(item:)` without a wrapper type.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
