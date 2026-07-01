import SwiftUI

@main
struct NewsReelApp: App {
    init() {
        AppFonts.register()
        configureImageDiskCache()
    }

    var body: some Scene {
        WindowGroup {
            FeedView()
                .preferredColorScheme(.dark)   // dark-forced for now
        }
    }

    private func configureImageDiskCache() {
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,    // 64 MB
            diskCapacity: 512 * 1024 * 1024      // 512 MB
        )
    }
}
