import SwiftUI
import UIKit

// MARK: - Image Cache (performance)
// Two-tier: NSCache holds decoded UIImages in memory; URLCache (configured at
// launch) holds raw bytes on disk. Built for fast scrolling in a lazy feed.
final class ImageMemoryCache {
    static let shared = ImageMemoryCache()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 80
        cache.totalCostLimit = 120 * 1024 * 1024   // ~120 MB decoded
    }

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func insert(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

// MARK: - Loader
@MainActor
final class ImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private var task: Task<Void, Never>?
    private var loadedURL: URL?

    func load(_ url: URL?, onLoaded: ((CGSize) -> Void)? = nil) {
        guard let url else { return }
        if loadedURL == url, image != nil { return }
        loadedURL = url

        if let cached = ImageMemoryCache.shared.image(for: url) {
            image = cached
            onLoaded?(cached.size)
            return
        }

        task?.cancel()
        task = Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let ui = UIImage(data: data) else { return }
                ImageMemoryCache.shared.insert(ui, for: url)
                guard !Task.isCancelled else { return }
                self?.image = ui
                onLoaded?(ui.size)
            } catch {
                // Silent — the gradient fallback remains visible.
            }
        }
    }

    func cancel() { task?.cancel() }
}

// MARK: - CachedAsyncImage
// Drop-in cover/inline image. Shows the per-story hue gradient while loading or
// on failure, then crossfades the photo in. Caller sets .frame(...) and clips.
//
// NB: deliberately NO GeometryReader — a greedy GeometryReader here corrupts the
// coordinate space of any ZStack it's placed in (pushed overlays off-screen).
struct CachedAsyncImage: View {
    let url: String
    let hue: Double
    /// `.fill` crops to fill the frame (default). `.fit` shows the whole image,
    /// letterboxed against the hue fallback — used for cards so nothing is cut.
    var contentMode: ContentMode = .fill
    /// Where the image sits within its frame when cropped (`.fill`). `.top`
    /// keeps the top edge intact and crops only the bottom — used when a
    /// caller caps a tall image's height instead of letterboxing it.
    var imageAlignment: Alignment = .center
    /// Reports the source image's native pixel size once decoded, so a caller
    /// can size its frame to the image's own aspect ratio instead of guessing.
    var onImageLoaded: ((CGSize) -> Void)? = nil
    @StateObject private var loader = ImageLoader()

    var body: some View {
        ZStack(alignment: imageAlignment) {
            LinearGradient.coverFallback(hue: hue)

            if let img = loader.image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .clipped()
        .onAppear { loader.load(URL(string: url), onLoaded: onImageLoaded) }
        .onDisappear { loader.cancel() }
        .animation(.easeOut(duration: 0.4), value: loader.image != nil)
    }
}
