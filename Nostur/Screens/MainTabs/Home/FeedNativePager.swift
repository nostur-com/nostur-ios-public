import SwiftUI

private struct FeedNativePagingOriginKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    var feedNativePagingOrigin: Int? {
        get { self[FeedNativePagingOriginKey.self] }
        set { self[FeedNativePagingOriginKey.self] = newValue }
    }
}

/// No observable drag state: native scrolling owns every movement/deceleration
/// frame. Selection (and therefore feed loading/resume) changes only at idle.
@MainActor
final class FeedNativePagingSession {
    private(set) var origin: Int?

    func begin(at index: Int) { origin = index }
    func cancel() { origin = nil }

    func finish(at index: Int) -> Int? {
        guard let origin else { return nil }
        self.origin = nil
        return index == origin ? nil : index - origin
    }

    nonisolated static func boundedTarget(start: Int, proposed: Int, pageCount: Int) -> Int {
        min(max(0, pageCount - 1), max(0, min(start + 1, max(start - 1, proposed))))
    }
}

private struct FeedNativeSelection: Equatable {
    let id: String
    let index: Int
}

@available(iOS 18.0, *)
struct FeedNativePager<Content: View>: View {
    let content: Content
    let isEnabled: Bool
    let pageCount: Int
    let selectedIndex: Int
    let selectionID: String
    let onSwipe: (Int) -> Void
    @State private var position = ScrollPosition()
    @State private var session = FeedNativePagingSession()

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                // Positions are absolute, so committing selection does not move
                // or recreate any page and does not require recentering the strip.
                content
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .environment(\.feedNativePagingOrigin, selectedIndex)
                    .frame(width: geometry.size.width * CGFloat(max(1, pageCount)),
                           height: geometry.size.height, alignment: .leading)
            }
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .scrollTargetBehavior(FeedNativePagingBehavior(pageCount: pageCount, selectedIndex: selectedIndex,
                                                        pageWidth: geometry.size.width))
            .scrollPosition($position)
            .defaultScrollAnchor(UnitPoint(x: pageCount > 1 ? CGFloat(selectedIndex) / CGFloat(pageCount - 1) : 0, y: 0), for: .initialOffset)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollDisabled(!isEnabled)
            .onScrollPhaseChange { _, phase, context in
                if phase == .interacting {
                    session.begin(at: selectedIndex)
                } else if phase == .idle {
                    let width = geometry.size.width
                    guard width > 0 else { session.cancel(); return }
                    let index = min(max(0, pageCount - 1), max(0, Int((context.geometry.contentOffset.x / width).rounded())))
                    guard let direction = session.finish(at: index) else { return }
                    // The native animation has finished before this can start
                    // Core Data reads, view initialization, or relay catch-up.
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { onSwipe(direction) }
                }
            }
            .onValueChange(FeedNativeSelection(id: selectionID, index: selectedIndex)) { _, _ in
                session.cancel()
                position.scrollTo(x: CGFloat(selectedIndex) * geometry.size.width)
            }
            .onValueChange(geometry.size) { _, size in
                session.cancel()
                position.scrollTo(x: CGFloat(selectedIndex) * size.width)
            }
            .onValueChange(isEnabled) { _, enabled in
                if !enabled { session.cancel() }
            }
            .onDisappear { session.cancel() }
        }
    }
}

@available(iOS 18.0, *)
private struct FeedNativePagingBehavior: ScrollTargetBehavior {
    let pageCount: Int
    let selectedIndex: Int
    let pageWidth: CGFloat

    @available(iOS 18.4, *)
    func properties(context: PropertiesContext) -> Properties {
        var properties = PagingScrollTargetBehavior().properties(context: context)
        properties.limitsScrolls = true
        return properties
    }

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        PagingScrollTargetBehavior().updateTarget(&target, context: context)
        guard pageWidth > 0 else { return }
        let proposed = Int((target.rect.minX / pageWidth).rounded())
        // An interrupted deceleration still belongs to the selected feed.
        // Bound against that feed, so another fling cannot reveal an unprepared
        // distant page or commit two feeds in one pending transition.
        let index = FeedNativePagingSession.boundedTarget(start: selectedIndex, proposed: proposed, pageCount: pageCount)
        target.rect.origin.x = CGFloat(index) * pageWidth
        target.rect.size.width = pageWidth
    }
}
