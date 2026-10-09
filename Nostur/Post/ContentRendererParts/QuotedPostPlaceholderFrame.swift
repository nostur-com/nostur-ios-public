import SwiftUI

/// Reserve seven body-text lines while fetching an embedded post.
struct QuotedPostPlaceholderFrame: ViewModifier {
    #if targetEnvironment(macCatalyst)
    @AppStorage(SettingsStore.Keys.macTextSize) private var macTextSize = SettingsStore.MacTextSizeOption.standard.rawValue
    #endif
    @ScaledMetric(relativeTo: .body) private var textHeight = UIFont.systemFont(ofSize: 17).lineHeight * 7

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        let scale = (SettingsStore.MacTextSizeOption(rawValue: macTextSize) ?? .standard).scale
        content.frame(height: textHeight * scale)
        #else
        content.frame(height: textHeight)
        #endif
    }
}
