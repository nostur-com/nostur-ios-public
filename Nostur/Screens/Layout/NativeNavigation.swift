//
//  NativeNavigation.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/09/2026.
//

import SwiftUI
import NavigationBackport

private struct NativeNavigationEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

private struct NativeSplitActiveKey: EnvironmentKey {
    static let defaultValue = false
}

private struct NosturAppendKey: EnvironmentKey {
    static let defaultValue: ((any IdentifiableDestination) -> Void)? = nil
}

extension EnvironmentValues {
    var nativeNavigationEnabled: Bool {
        get { self[NativeNavigationEnabledKey.self] }
        set { self[NativeNavigationEnabledKey.self] = newValue }
    }

    /// True while the iOS 27 shell is showing the regular-width feed/detail split.
    /// Tab stacks push only when this is false. The detail pane consumes `.navigateTo` when it is true.
    var nativeSplitActive: Bool {
        get { self[NativeSplitActiveKey.self] }
        set { self[NativeSplitActiveKey.self] = newValue }
    }

    /// When set, DM and other in-stack pushes append here instead of an `NBNavigationPath`.
    var nosturAppend: ((any IdentifiableDestination) -> Void)? {
        get { self[NosturAppendKey.self] }
        set { self[NosturAppendKey.self] = newValue }
    }
}

private struct NosturNavigationStackModifier: ViewModifier {
    @Environment(\.nativeNavigationEnabled) private var nativeNavigationEnabled

    func body(content: Content) -> some View {
        content.nbUseNavigationStack(nativeNavigationEnabled ? .whenAvailable : .never)
    }
}

extension View {
    func nosturNavigationStackCompat() -> some View {
        modifier(NosturNavigationStackModifier())
    }
}

@available(iOS 27.1, *)
struct NativePhoneSplit<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.theme) private var theme
    @ObservedObject var detailTabs: DetailTabsModel
    @StateObject private var detailPlayback = VideoPostPlaybackCoordinator()
    @ViewBuilder let content: Content
    // A phone-sized reading column, independent of transitional display widths.
    private let preferredFeedWidth: CGFloat = 390

    var body: some View {
        GeometryReader { geometry in
            let isExpanded = horizontalSizeClass == .regular
            let availableWidth = geometry.size.width
            let feedWidth = isExpanded ? min(preferredFeedWidth, max(0, availableWidth - 280)) : availableWidth
            let detailWidth = max(280, availableWidth - feedWidth)

            HStack(spacing: 0) {
                // Keep the detail subtree alive while folded and across feed tab changes.
                AvailableWidthContainer {
                    DetailPane(tm: detailTabs, embeddedInNativeSplit: true)
                        .environment(\.containerID, "DetailPane")
                        .environmentObject(detailPlayback)
                        .background(theme.listBackground)
                }
                .frame(width: detailWidth)
                .frame(width: isExpanded ? detailWidth : 0, alignment: .leading)
                .clipped()
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)

                AvailableWidthContainer {
                    content
                }
                .frame(width: feedWidth)
            }
        }
    }

}

/// Tab stacks push on compact width, and on iPad only when there is no detail column.
/// The iOS 27 shell sets `nativeSplitActive` whenever its split is showing the detail column.
func tabStackShouldPush(nativeSplitActive: Bool, horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
    if nativeSplitActive { return false }
    if IS_IPAD && horizontalSizeClass != .compact { return false }
    return true
}

@available(iOS 16.0, *)
extension NavigationPath {
    mutating func append(destination: any IdentifiableDestination) {
        switch destination {
        case let value as NRPost: append(value)
        case let value as NRContact: append(value)
        case let value as NRLiveEvent: append(value)
        case let value as NRContactPath: append(value)
        case let value as NotePath: append(value)
        case let value as ContactPath: append(value)
        case let value as HashtagPath: append(value)
        case let value as Nevent1Path: append(value)
        case let value as Naddr1Path: append(value)
        case let value as ArticlePath: append(value)
        case let value as Nprofile1Path: append(value)
        case let value as ArticleCommentsPath: append(value)
        case let value as YearReviewPath: append(value)
        case let value as NewDMConversation: append(value)
        case let value as DMConversation: append(value)
        case let value as ViewPath: append(value)
        case let value as Badge: append(value)
        case let value as CloudFeed: append(value)
        default:
#if DEBUG
            L.og.debug("NavigationPath dropped \(String(describing: type(of: destination)))")
#endif
            break
        }
    }
}
