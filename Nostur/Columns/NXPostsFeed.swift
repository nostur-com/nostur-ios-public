//
//  NXPostsFeed.swift
//  Nosturix
//
//  Created by Fabian Lachman on 01/08/2024.
//

import SwiftUI
import QuartzCore
@_spi(Advanced) import SwiftUIIntrospect
import Combine

private struct NXFeedLayoutStabilizerKey: EnvironmentKey {
    static let defaultValue: NXFeedLayoutStabilizer? = nil
}

extension EnvironmentValues {
    var feedLayoutStabilizer: NXFeedLayoutStabilizer? {
        get { self[NXFeedLayoutStabilizerKey.self] }
        set { self[NXFeedLayoutStabilizerKey.self] = newValue }
    }
}

/// Applies asynchronous row-height changes without moving the post the user is reading.
/// Updates are deferred during drag/deceleration, then the first visible row is restored to
/// the same viewport position after self-sizing layout completes.
@MainActor
final class NXFeedLayoutStabilizer: ObservableObject {
    private struct PendingUpdate {
        let reason: String
        let apply: () -> Void
    }

    private weak var scrollView: UIScrollView?
    private var itemIDs: [String] = []
    private var pendingUpdates: [PendingUpdate] = []
    private var pendingPinByIdentity = false
    private var flushTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var isProgrammaticScrollInProgress = false
    private var isSuspended = false
    private var lastKnownAnchor: (id: String, visibleTopOffset: CGFloat)?
    private var suspendedAnchor: (id: String, visibleTopOffset: CGFloat)?
    private var pendingRestoreAnchor: (id: String, visibleTopOffset: CGFloat)?
    private var anchorGeneration = 0
    private var lastContentOffsetY: CGFloat = 0
    private var lastInsetTop: CGFloat = 0
    private var lastUserScrollAt: CFTimeInterval = 0
    private var scrollObservations: [NSKeyValueObservation] = []
    private var lastApproachingBottomSignalAt: CFTimeInterval = 0
    /// Fired on content-offset changes (status-bar tap-to-top, fling, etc.).
    var onViewportChange: (() -> Void)?
    /// Fired at a low frequency when less than a few screens of content remain.
    var onApproachingBottom: (() -> Void)?
#if DEBUG
    var onDebugAction: ((String) -> Void)?
#endif

    var isProgrammaticScrollPending: Bool {
        isProgrammaticScrollInProgress
    }

    func attach(to scrollView: UIScrollView) {
        let replaced = self.scrollView !== scrollView
        self.scrollView = scrollView
        if replaced {
            observeScrollGeometry(of: scrollView)
        }
        guard replaced, !isSuspended, let anchor = pendingRestoreAnchor else { return }
        pendingRestoreAnchor = nil
        startSettling(anchor: anchor, extended: true, bringOnScreen: true)
    }

    func updateItemIDs(_ itemIDs: [String]) {
        self.itemIDs = itemIDs
    }

    func rememberAnchor(id: String, visibleTopOffset: CGFloat = 0) {
        lastKnownAnchor = (id, visibleTopOffset)
        if let scrollView {
            lastContentOffsetY = scrollView.contentOffset.y
            lastInsetTop = scrollView.adjustedContentInset.top
        }
    }

    func visiblePostID() -> String? {
        guard let scrollView, scrollView.window != nil else { return lastKnownAnchor?.id }
        return visibleAnchor(in: scrollView)?.id ?? lastKnownAnchor?.id
    }

    /// Preserve reading position across tab/detail navigation. Row content can finish resolving
    /// while its List is hidden, when UIKit's visible-cell anchoring is not reliable.
    func suspendPositionTracking() {
        if let scrollView {
            suspendedAnchor = visibleAnchor(in: scrollView) ?? lastKnownAnchor ?? suspendedAnchor
        } else {
            suspendedAnchor = lastKnownAnchor ?? suspendedAnchor
        }
        isSuspended = true
        cancelPendingWork()

        let updates = pendingUpdates
        pendingUpdates.removeAll()
        pendingPinByIdentity = false
        updates.forEach { $0.apply() }
    }

    func resumePositionTracking() {
        isSuspended = false
        guard let anchor = suspendedAnchor else { return }
        suspendedAnchor = nil
        lastKnownAnchor = anchor
        startSettling(anchor: anchor, extended: true, bringOnScreen: true)
    }

    func beginProgrammaticScroll() {
        isProgrammaticScrollInProgress = true
        settleTask?.cancel()
        settleTask = nil
        anchorGeneration += 1
    }

    func cancelProgrammaticScroll() {
        isProgrammaticScrollInProgress = false
        scheduleFlush()
    }

    /// Bottom inserts must not run a leftover prepend settle / restore pin.
    func cancelPendingSettle() {
        anchorGeneration += 1
        settleTask?.cancel()
        settleTask = nil
        pendingRestoreAnchor = nil
    }

    func finishProgrammaticScroll(finalPosition: () -> Void) async {
        flushTask?.cancel()
        flushTask = nil

        guard let scrollView else {
            let updates = pendingUpdates
            pendingUpdates.removeAll()
            pendingPinByIdentity = false
            updates.forEach { $0.apply() }
            finalPosition()
            isProgrammaticScrollInProgress = false
            return
        }

        let updates = pendingUpdates
        pendingUpdates.removeAll()
        pendingPinByIdentity = false

        // Keep programmatic-scroll blocking until after the final pin so a row-height
        // change applied here cannot start a competing settle (visible as a jump).

        // Most unread jumps do not have a pending row-height change. In that common case a
        // snapshot only causes a visible one-frame flash, so settle the final position directly.
        guard !updates.isEmpty else {
            scrollView.layoutIfNeeded()
            finalPosition()
            scrollView.layoutIfNeeded()
            isProgrammaticScrollInProgress = false
            return
        }

        // SwiftUI reconciles the resolved repost and UIKit corrects the self-sized row on
        // separate layout passes. Cover those passes with the already-rendered viewport so the
        // user never sees the temporary wrong offset between resize and final positioning.
        let snapshot = scrollView.snapshotView(afterScreenUpdates: false)
        if let snapshot, let superview = scrollView.superview {
            snapshot.frame = scrollView.frame
            snapshot.isUserInteractionEnabled = false
            superview.addSubview(snapshot)
        }

        updates.forEach { $0.apply() }

        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        scrollView.layoutIfNeeded()
        finalPosition()
        scrollView.layoutIfNeeded()

        snapshot?.removeFromSuperview()
        isProgrammaticScrollInProgress = false
    }

    /// Pins `id` to the visible top. No-ops when it is already there so an unread
    /// animation that landed correctly is not followed by a second scrollToItem jump.
    func pinItemToVisibleTop(id: String) {
        guard let scrollView, scrollView.window != nil else {
            rememberAnchor(id: id, visibleTopOffset: 0)
            return
        }
        rememberAnchor(id: id, visibleTopOffset: 0)

        guard let itemIndex = itemIDs.firstIndex(of: id),
              let indexPath = NXFeedIndexMapping.indexPath(
                forItemIndex: itemIndex,
                sectionCounts: sectionCounts(in: scrollView),
                itemCount: itemIDs.count
              ) else {
            restore(anchor: (id, 0), in: scrollView, bringOnScreen: true)
            return
        }

        guard let minY = itemMinY(at: indexPath, in: scrollView) else {
            restore(anchor: (id, 0), in: scrollView, bringOnScreen: true)
            return
        }

        let visibleTopOffset = NXFeedViewport.offsetFromVisibleTop(
            itemMinY: minY,
            contentOffsetY: scrollView.contentOffset.y,
            insetTop: scrollView.adjustedContentInset.top
        )
        guard abs(visibleTopOffset) > 1.5 else { return }

        let visibleMinY = scrollView.contentOffset.y
        let visibleMaxY = visibleMinY + scrollView.bounds.height
        let isOnScreen = minY < visibleMaxY && minY + 1 > visibleMinY
        restore(anchor: (id, 0), in: scrollView, bringOnScreen: !isOnScreen)
    }

    func performAnchored(
        reason: String = "row layout change",
        pinByIdentity: Bool = false,
        _ update: @escaping () -> Void
    ) {
        let pendingUpdate = PendingUpdate(reason: reason, apply: update)
        if isSuspended {
            update()
            return
        }

        guard let scrollView, scrollView.window != nil else {
            pendingRestoreAnchor = lastKnownAnchor ?? pendingRestoreAnchor
            update()
            return
        }

        if isProgrammaticScrollInProgress || isUserScrollingOrRecently(in: scrollView) {
            pendingUpdates.append(pendingUpdate)
            pendingPinByIdentity = pendingPinByIdentity || pinByIdentity
#if DEBUG
            onDebugAction?(
                "queued \(reason) while \(scrollMotion(in: scrollView)) · \(itemIDs.count) posts · pending \(pendingUpdates.count) · \(anchorSummary(in: scrollView))"
            )
#endif
            scheduleFlush()
        } else {
            applyAnchored([pendingUpdate], pinByIdentity: pinByIdentity)
        }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isProgrammaticScrollInProgress
                    || self.scrollView.map({ self.isUserScrollingOrRecently(in: $0) }) == true {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
            }
            let updates = self.pendingUpdates
            let pinByIdentity = self.pendingPinByIdentity
            self.pendingUpdates.removeAll()
            self.pendingPinByIdentity = false
            self.flushTask = nil
#if DEBUG
            if !updates.isEmpty {
                let reasons = updates.map(\.reason).uniqued()
                self.onDebugAction?(
                    "scroll idle · applying \(updates.count) queued update\(updates.count == 1 ? "" : "s") [\(reasons.joined(separator: ", "))] · \(self.anchorSummary(in: self.scrollView))"
                )
            }
#endif
            self.applyAnchored(updates, pinByIdentity: pinByIdentity)
        }
    }

    private func isUserScrollingOrRecently(in scrollView: UIScrollView) -> Bool {
        scrollView.isDragging
            || scrollView.isDecelerating
            || scrollView.isTracking
            || (lastUserScrollAt > 0 && CACurrentMediaTime() - lastUserScrollAt < 0.5)
    }

    private func applyAnchored(_ updates: [PendingUpdate], pinByIdentity: Bool) {
        guard !updates.isEmpty else { return }

        let oldIDs = itemIDs
        let capturedAnchor = (scrollView.flatMap { visibleAnchor(in: $0) })
            ?? lastKnownAnchor
            ?? pendingRestoreAnchor

        updates.forEach { $0.apply() }

#if DEBUG
        let addedCount = itemIDs.count { !oldIDs.contains($0) }
        let removedCount = oldIDs.count { !itemIDs.contains($0) }
        if addedCount > 0 || removedCount > 0 {
            onDebugAction?(
                "feed IDs changed · \(oldIDs.count)→\(itemIDs.count) · +\(addedCount)/−\(removedCount) · \(anchorSummary(in: scrollView))"
            )
        }
#endif

        let insertedAbove = capturedAnchor.map {
            NXFeedIndexMapping.itemsInsertedAbove(oldIDs: oldIDs, newIDs: itemIDs, anchorID: $0.id)
        } ?? false
        let needsExtendedSettling = pinByIdentity || insertedAbove

        // Self-sizing row changes do not alter feed identity. UICollectionView/TableView
        // already account for those layout changes; applying our own correction afterward
        // can visibly move the feed a second time. Manual settling is reserved for an actual
        // prepend (or an explicit identity pin), where UIKit cannot infer our intended anchor.
        guard needsExtendedSettling else {
            pendingRestoreAnchor = nil
            if let currentAnchor = scrollView.flatMap({ visibleAnchor(in: $0) }) {
                lastKnownAnchor = currentAnchor
            }
#if DEBUG
            let reasons = updates.map(\.reason).uniqued().joined(separator: ", ")
            onDebugAction?(
                "applied \(reasons) · no manual correction · UIKit owns viewport · \(anchorSummary(in: scrollView))"
            )
#endif
            return
        }

        guard let anchor = capturedAnchor else { return }
        lastKnownAnchor = anchor

        guard let scrollView, scrollView.window != nil else {
            pendingRestoreAnchor = anchor
            return
        }

        // A normal prepend starts with the anchor already visible. Calling
        // scrollToItem before SwiftUI's List has reconciled its new indices can
        // target the old row at that index and jump backward several posts.
        startSettling(
            anchor: anchor,
            extended: needsExtendedSettling,
            bringOnScreen: pinByIdentity
        )
    }

    private func startSettling(
        anchor: (id: String, visibleTopOffset: CGFloat),
        extended: Bool,
        bringOnScreen: Bool
    ) {
        anchorGeneration += 1
        let generation = anchorGeneration
        settleTask?.cancel()
        pendingRestoreAnchor = anchor
        lastKnownAnchor = anchor

        // Prepends need a few frames for estimated rows to self-size. Ordinary
        // image/repost height changes only need one or two offset corrections.
        // Never run this loop during a user drag: it would fight the scroller.
        let maxSteps = extended ? 8 : 2

        settleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var didBringOnScreen = false
            var stableSamples = 0
#if DEBUG
            let startingOffset = self.scrollView?.contentOffset.y
            var correctionCount = 0
#endif

            for step in 0..<maxSteps {
                guard !Task.isCancelled,
                      !self.isSuspended,
                      self.anchorGeneration == generation else { return }

                if self.scrollView?.isDragging == true
                    || self.scrollView?.isDecelerating == true
                    || self.scrollView?.isTracking == true {
                    self.lastUserScrollAt = CACurrentMediaTime()
                    self.pendingRestoreAnchor = nil
                    return
                }

                if self.scrollView == nil || self.scrollView?.window == nil {
                    self.pendingRestoreAnchor = anchor
                    return
                }

                if step == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: 16_000_000)
                }
                guard !Task.isCancelled,
                      !self.isSuspended,
                      self.anchorGeneration == generation,
                      let scrollView = self.scrollView,
                      scrollView.window != nil,
                      !scrollView.isDragging,
                      !scrollView.isDecelerating,
                      !scrollView.isTracking else {
                    self.pendingRestoreAnchor = nil
                    return
                }

                let shouldBringOnScreen = bringOnScreen && !didBringOnScreen
                let didCorrect = self.restore(
                    anchor: anchor,
                    in: scrollView,
                    bringOnScreen: shouldBringOnScreen
                )
                if shouldBringOnScreen {
                    didBringOnScreen = true
                }

                if didCorrect {
                    stableSamples = 0
#if DEBUG
                    correctionCount += 1
#endif
                } else {
                    stableSamples += 1
                    if stableSamples >= 2 {
                        self.pendingRestoreAnchor = nil
#if DEBUG
                        self.recordSettlingResult(
                            anchor: anchor,
                            correctionCount: correctionCount,
                            startingOffset: startingOffset
                        )
#endif
                        return
                    }
                }
            }

            if self.anchorGeneration == generation {
                self.pendingRestoreAnchor = nil
#if DEBUG
                self.recordSettlingResult(
                    anchor: anchor,
                    correctionCount: correctionCount,
                    startingOffset: startingOffset
                )
#endif
            }
        }
    }

#if DEBUG
    private func recordSettlingResult(
        anchor: (id: String, visibleTopOffset: CGFloat),
        correctionCount: Int,
        startingOffset: CGFloat?
    ) {
        guard correctionCount > 0 else { return }
        let start = startingOffset.map { String(format: "%.1f", $0) } ?? "?"
        let end = scrollView.map { String(format: "%.1f", $0.contentOffset.y) } ?? "?"
        onDebugAction?(
            "viewport corrected \(correctionCount)× · y \(start)→\(end) · anchor \(shortID(anchor.id)) @ \(String(format: "%.1f", anchor.visibleTopOffset))"
        )
    }

    private func scrollMotion(in scrollView: UIScrollView) -> String {
        if scrollView.isDragging || scrollView.isTracking { return "dragging" }
        if scrollView.isDecelerating { return "decelerating" }
        if isProgrammaticScrollInProgress { return "programmatic scroll" }
        return "recent scrolling"
    }

    private func anchorSummary(in scrollView: UIScrollView?) -> String {
        let anchor = scrollView.flatMap { visibleAnchor(in: $0) } ?? lastKnownAnchor
        let anchorText = anchor.map {
            "anchor \(shortID($0.id)) @ \(String(format: "%.1f", $0.visibleTopOffset))"
        } ?? "anchor none"
        let offset = scrollView.map { String(format: "%.1f", $0.contentOffset.y) } ?? "?"
        return "\(anchorText) · y \(offset)"
    }

    private func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }
#endif

    @discardableResult
    private func restore(
        anchor: (id: String, visibleTopOffset: CGFloat),
        in scrollView: UIScrollView,
        bringOnScreen: Bool = false
    ) -> Bool {
        guard let itemIndex = itemIDs.firstIndex(of: anchor.id) else { return false }
        let sectionCounts = sectionCounts(in: scrollView)
        guard let indexPath = NXFeedIndexMapping.indexPath(
            forItemIndex: itemIndex,
            sectionCounts: sectionCounts,
            itemCount: itemIDs.count
        ) else { return false }

        if bringOnScreen {
            scrollToItem(at: indexPath, in: scrollView)
        }

        guard let newMinY = itemMinY(at: indexPath, in: scrollView) else { return bringOnScreen }
        let currentVisibleTopOffset = NXFeedViewport.offsetFromVisibleTop(
            itemMinY: newMinY,
            contentOffsetY: scrollView.contentOffset.y,
            insetTop: scrollView.adjustedContentInset.top
        )
        let correction = currentVisibleTopOffset - anchor.visibleTopOffset
        guard abs(correction) > 0.5 else { return bringOnScreen }

        var offset = scrollView.contentOffset
        offset.y += correction
        let minOffsetY = -scrollView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        offset.y = min(max(offset.y, minOffsetY), maxOffsetY)
        scrollView.setContentOffset(offset, animated: false)
        lastContentOffsetY = scrollView.contentOffset.y
        lastInsetTop = scrollView.adjustedContentInset.top
        return true
    }

    private func visibleAnchor(in scrollView: UIScrollView) -> (id: String, visibleTopOffset: CGFloat)? {
        let indexPaths: [IndexPath]
        if let collectionView = scrollView as? UICollectionView {
            indexPaths = collectionView.indexPathsForVisibleItems
        } else if let tableView = scrollView as? UITableView {
            indexPaths = tableView.indexPathsForVisibleRows ?? []
        } else {
            return nil
        }

        let top = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        let candidates = indexPaths.compactMap { indexPath -> (IndexPath, CGRect)? in
            guard let frame = itemFrame(at: indexPath, in: scrollView) else { return nil }
            return (indexPath, frame)
        }
        guard let anchorIndex = NXFeedViewport.topEdgeAnchorIndex(
            itemFrames: candidates.map(\.1),
            visibleTopY: top
        ),
              let anchor = candidates[safe: anchorIndex] else { return nil }

        let sectionCounts = sectionCounts(in: scrollView)
        guard let itemIndex = NXFeedIndexMapping.itemIndex(
            for: anchor.0,
            sectionCounts: sectionCounts,
            itemCount: itemIDs.count
        ),
              let id = itemIDs[safe: itemIndex] else { return nil }
        let visibleTopOffset = NXFeedViewport.offsetFromVisibleTop(
            itemMinY: anchor.1.minY,
            contentOffsetY: scrollView.contentOffset.y,
            insetTop: scrollView.adjustedContentInset.top
        )
        let resolved = (id, visibleTopOffset)
        lastKnownAnchor = resolved
        lastContentOffsetY = scrollView.contentOffset.y
        lastInsetTop = scrollView.adjustedContentInset.top
        return resolved
    }

    private func itemMinY(at indexPath: IndexPath, in scrollView: UIScrollView) -> CGFloat? {
        itemFrame(at: indexPath, in: scrollView)?.minY
    }

    private func itemFrame(at indexPath: IndexPath, in scrollView: UIScrollView) -> CGRect? {
        if let collectionView = scrollView as? UICollectionView {
            return collectionView.layoutAttributesForItem(at: indexPath)?.frame
        }
        if let tableView = scrollView as? UITableView,
           tableView.numberOfSections > indexPath.section,
           tableView.numberOfRows(inSection: indexPath.section) > indexPath.row {
            return tableView.rectForRow(at: indexPath)
        }
        return nil
    }

    private func sectionCounts(in scrollView: UIScrollView) -> [Int] {
        if let collectionView = scrollView as? UICollectionView {
            return (0..<collectionView.numberOfSections).map { collectionView.numberOfItems(inSection: $0) }
        }
        if let tableView = scrollView as? UITableView {
            return (0..<tableView.numberOfSections).map { tableView.numberOfRows(inSection: $0) }
        }
        return []
    }

    private func scrollToItem(at indexPath: IndexPath, in scrollView: UIScrollView) {
        if let collectionView = scrollView as? UICollectionView,
           collectionView.numberOfSections > indexPath.section,
           collectionView.numberOfItems(inSection: indexPath.section) > indexPath.item {
            collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
        } else if let tableView = scrollView as? UITableView,
                  tableView.numberOfSections > indexPath.section,
                  tableView.numberOfRows(inSection: indexPath.section) > indexPath.row {
            tableView.scrollToRow(at: indexPath, at: .top, animated: false)
        }
    }

    private func cancelPendingWork() {
        anchorGeneration += 1
        flushTask?.cancel()
        flushTask = nil
        settleTask?.cancel()
        settleTask = nil
    }

    private func observeScrollGeometry(of scrollView: UIScrollView) {
        scrollObservations.removeAll()
        lastContentOffsetY = scrollView.contentOffset.y
        lastInsetTop = scrollView.adjustedContentInset.top

        scrollObservations.append(scrollView.observe(\.adjustedContentInset, options: [.old, .new]) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                self?.handleAdjustedContentInsetChange(in: scrollView)
            }
        })
        scrollObservations.append(scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                self?.handleContentOffsetChange(in: scrollView)
            }
        })
        scrollObservations.append(scrollView.observe(\.contentSize, options: [.new]) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                self?.evaluateApproachingBottom(in: scrollView)
            }
        })
    }

    private func handleContentOffsetChange(in scrollView: UIScrollView) {
        lastContentOffsetY = scrollView.contentOffset.y
        lastInsetTop = scrollView.adjustedContentInset.top
        if scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking {
            lastUserScrollAt = CACurrentMediaTime()
        }
        onViewportChange?()
        evaluateApproachingBottom(in: scrollView)
    }

    private func evaluateApproachingBottom(in scrollView: UIScrollView) {
        guard scrollView.window != nil, scrollView.bounds.height > 0 else { return }
        let visibleBottom = scrollView.contentOffset.y
            + scrollView.bounds.height
            - scrollView.adjustedContentInset.bottom
        let remaining = max(0, scrollView.contentSize.height - visibleBottom)
        let prefetchDistance = max(1_200, scrollView.bounds.height * 2.5)
        guard remaining <= prefetchDistance else { return }

        let now = CACurrentMediaTime()
        guard now - lastApproachingBottomSignalAt >= 0.35 else { return }
        lastApproachingBottomSignalAt = now
        onApproachingBottom?()
    }

    private func handleAdjustedContentInsetChange(in scrollView: UIScrollView) {
        let newInsetTop = scrollView.adjustedContentInset.top
        let oldInsetTop = lastInsetTop
        guard abs(newInsetTop - oldInsetTop) > 0.5 else {
            lastInsetTop = newInsetTop
            return
        }

        let isUserScrolling = scrollView.isDragging
            || scrollView.isDecelerating
            || scrollView.isTracking
        if isUserScrolling {
            lastUserScrollAt = CACurrentMediaTime()
        }

        // Live banner / safe-area inset changes should not move the post under the visible top.
        // Skip during a finger drag and for a short time after, so tab-bar minimize
        // inset animation cannot fight the scroller.
        if isSuspended || isUserScrolling || CACurrentMediaTime() - lastUserScrollAt < 0.4 {
            lastInsetTop = newInsetTop
            lastContentOffsetY = scrollView.contentOffset.y
            return
        }

        let currentOffset = scrollView.contentOffset.y
        let desired = NXFeedViewport.contentOffset(
            preservingVisibleContent: lastContentOffsetY,
            oldInsetTop: oldInsetTop,
            newInsetTop: newInsetTop
        )
        let uikitAlreadyPreserved = abs(currentOffset - desired) <= 0.5
        let offsetStillAtLastKnown = abs(currentOffset - lastContentOffsetY) <= 0.5

        lastInsetTop = newInsetTop

        // If the user has scrolled since we last recorded an offset, do not jump back.
        // Compensate only when the offset is still the one we know, or UIKit already
        // applied the exact preservation we want.
        guard offsetStillAtLastKnown || uikitAlreadyPreserved else {
            lastContentOffsetY = currentOffset
            return
        }
        guard !uikitAlreadyPreserved else {
            lastContentOffsetY = currentOffset
            return
        }

        var offset = scrollView.contentOffset
        offset.y = desired
        let minOffsetY = -newInsetTop
        let maxOffsetY = max(
            minOffsetY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        offset.y = min(max(offset.y, minOffsetY), maxOffsetY)

        scrollView.setContentOffset(offset, animated: false)
        lastContentOffsetY = scrollView.contentOffset.y
    }
}

struct NXPostsFeed: View {
    
    @Environment(\.theme) private var theme
    @Environment(\.availableWidth) private var availableWidth
    @Environment(\.availableHeight) private var availableHeight
    
    @ObservedObject private var vm: NXColumnViewModel
    private let posts: [NRPost]
    private let vmInner: NXColumnViewModelInner

    @State private var updateIsAtTopSubscription: AnyCancellable?
    @StateObject private var layoutStabilizer = NXFeedLayoutStabilizer()
    
    init(vm: NXColumnViewModel, posts: [NRPost]) {
        self.vm = vm
        self.posts = posts
        self.vmInner = vm.vmInner
    }

    private var relayFeedRelays: Set<RelayData> {
        guard let config = vm.config else { return [] }

        switch config.columnType {
        case .relays(let feed):
            return feed.relaysData
        case .relayPreview(let relayData):
            return [relayData]
        default:
            return []
        }
    }

    private var feedImageTargetSize: CGSize {
        feedImageRequestTargetSize(
            for: availableWidth,
            availableHeight: availableHeight
        )
    }

    /// Row-based fallback for cases where UIKit has not reported useful content geometry yet.
    private var paginationLeadPostId: String? {
        let leadCount = min(8, max(4, posts.count / 3))
        guard posts.count > leadCount else { return posts.last?.id }
        return posts[posts.count - leadCount].id
    }
    
    var body: some View {
        // Keep List as the top-level scroll container (no GeometryReader parent) so iOS 26
        // tabBarMinimizeBehavior(.onScrollDown) can observe it as the primary scroller.
        List {
            ForEach(posts) { nrPost in
                NXListRow(nrPost: nrPost, vm: vm) {
                    PostOrThread(nrPost: nrPost, theme: theme)
                        .environment(\.availableHeight, availableHeight)
                        .environment(\.availableWidth, availableWidth)
                        .environment(
                            \.feedImageRequestTargetSize,
                            feedImageTargetSize
                        )
                        .environment(\.relayFeedRelays, relayFeedRelays)
                        .environment(\.feedLayoutStabilizer, layoutStabilizer)
                }
                .onAppear {
                    if nrPost.id == paginationLeadPostId, let oldest = posts.last {
                        vm.requestNextPageIfNeeded(until: oldest.created_at, trigger: "lead row")
                    }
                }
                .onDisappear {
                    onPostDisappear(nrPost)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            if let oldestPost = posts.last {
                Color.clear
                    .frame(height: 1)
                    .id("pagination-\(oldestPost.id)")
                    .onAppear {
                        vm.requestNextPageIfNeeded(until: oldestPost.created_at, trigger: "tail sentinel")
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init())

                if vm.isLoadingOlderPage {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .frame(minHeight: 44)
                    .id("pagination-progress-\(oldestPost.id)")
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init())
                    .accessibilityLabel("Loading older posts")
                }
            }
        }
        .withContainerTopOffsetEnvironmentKey()
        .scrollOffsetID(vm.columnVMid)
        .environment(\.defaultMinListRowHeight, 50)
        .listStyle(.plain)
        .introspect(.list, on: .iOS(.v15)) { [weak vm] view in
            guard let vm else { return }
            vm.tableView = view
            layoutStabilizer.attach(to: view)
            restorePreparedScrollPositionIfNeeded(in: view)
            DispatchQueue.main.async {
                if vm.tablePrefetcher == nil {
                    vm.tablePrefetcher = NXPostsFeedTablePrefetcher()
                    vm.tablePrefetcher?.columnViewModel = vm
                    view.isPrefetchingEnabled = true
                    view.prefetchDataSource = vm.tablePrefetcher
                }
                vm.tablePrefetcher?.imageRequestTargetSize =
                    feedImageTargetSize
            }
        }
        .introspect(.list, on: .iOS(.v16...)) { [weak vm] view in
            guard let vm else { return }
            vm.collectionView = view
            layoutStabilizer.attach(to: view)
            restorePreparedScrollPositionIfNeeded(in: view)
            DispatchQueue.main.async {
                if vm.collectionPrefetcher == nil {
                    vm.collectionPrefetcher = NXPostsFeedPrefetcher()
                    vm.collectionPrefetcher?.columnViewModel = vm
                    view.isPrefetchingEnabled = true
                    view.prefetchDataSource = vm.collectionPrefetcher
                }
                vm.collectionPrefetcher?.imageRequestTargetSize =
                    feedImageTargetSize
            }
        }
        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
        .onAppear {
            vmInner.performAnchoredFeedUpdate = { [weak layoutStabilizer] reason, update in
                guard let layoutStabilizer else {
                    _ = update()
                    return
                }
                // Do not force pinByIdentity here. Cross-column unread removals would
                // scrollToItem every other Mac column. Prepends still pin via itemsInsertedAbove.
                layoutStabilizer.performAnchored(reason: reason) {
                    let itemIDs = update()
                    // Make the post-ID lookup deterministic for the correction pass rather than
                    // depending on SwiftUI's onChange delivery order after the List mutation.
                    layoutStabilizer.updateItemIDs(itemIDs)
                }
            }
            layoutStabilizer.updateItemIDs(posts.map(\.id))
            layoutStabilizer.onViewportChange = { [weak vmInner] in
                vmInner?.updateIsAtTopSubject.send()
            }
            layoutStabilizer.onApproachingBottom = { [weak vm] in
                guard let vm, let oldest = vm.currentNRPostsOnScreen.last else { return }
                vm.requestNextPageIfNeeded(
                    until: oldest.created_at,
                    trigger: "2.5-screen threshold"
                )
            }
#if DEBUG
            layoutStabilizer.onDebugAction = { [weak vm] message in
                vm?.feedActionDebugRecord?(message)
            }
#endif
            vmInner.cancelPendingFeedSettle = { [weak layoutStabilizer] in
                layoutStabilizer?.cancelPendingSettle()
            }
            if let readingID = vmInner.readingPostID ?? vmInner.pendingScrollToPostID {
                layoutStabilizer.rememberAnchor(id: readingID)
            }
            layoutStabilizer.resumePositionTracking()
        }
        .onChange(of: posts.map(\.id)) { itemIDs in
            // The stabilizer must resolve anchors by post identity after insertions/removals.
            // Index paths are not stable when unread posts are inserted above the viewport.
            layoutStabilizer.updateItemIDs(itemIDs)
        }
        .onChange(of: feedImageTargetSize) { newTargetSize in
            updatePrefetchImageTargetSize(newTargetSize)
        }
        .onReceive(vmInner.scrollToIndexSubject.compactMap { $0 }) { scrollToIndex in
            guard !vmInner.isPerformingScroll,
                  !vmInner.isPerformingScrollToFirstUnread else {
                vmInner.clearScrollRequest()
                return
            }
            
#if DEBUG
            L.og.debug("☘️☘️ \(vm.config?.name ?? "?") NXPostsFeed .isAtTop \(vmInner.isAtTop) scroll request \(scrollToIndex.description) -[LOG]-")
#endif
            
            performScrollToIndex(scrollToIndex)
        }
        .overlay(alignment: .topTrailing) {
            unreadCounterView
        }
        .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
            guard vm.isVisible else { return }
            scrollToFirstUnread()
        }
        .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
            guard vm.isVisible else { return }
            
            scrollToTop()
        }
        
        // Handle going to detail and back
        .onAppear {
            vm.resumeViewUpdates()
            updatePrefetchImageTargetSize(feedImageTargetSize)
            
            // Add updateIsAtTop() debounces - increase debounce time for better performance
            guard updateIsAtTopSubscription == nil else { return }
            updateIsAtTopSubscription = vmInner.updateIsAtTopSubject
                .debounce(for: 0.15, scheduler: RunLoop.main) // Increased from 0.075 for smoother scrolling
                .sink {
                    self._updateIsAtTop()
                }
        }
        .onDisappear {
            // When opening detail, the feed would still update in background using withAnimation { },
            // but because its not visible the hack to keep scroll position doesn't work
            // so we pause() updates (and resume() in onAppear {})
            layoutStabilizer.suspendPositionTracking()
            layoutStabilizer.onViewportChange = nil
            layoutStabilizer.onApproachingBottom = nil
#if DEBUG
            layoutStabilizer.onDebugAction = nil
#endif
            vm.pauseViewUpdates()
            vmInner.performAnchoredFeedUpdate = nil
            vmInner.cancelPendingFeedSettle = nil
        }
    }

    private func updatePrefetchImageTargetSize(_ targetSize: CGSize) {
        vm.tablePrefetcher?.imageRequestTargetSize = targetSize
        vm.collectionPrefetcher?.imageRequestTargetSize = targetSize
    }
    
    @ViewBuilder
    public var unreadCounterView: some View {
        NXUnreadCounterView(
            unreadState: vm.vmInner.unreadState,
            onTap: scrollToFirstUnread,
            onLongPress: scrollToTop
        )
            .padding(.trailing, 10)
            .padding(.top, 5)
    }
    
    private func scrollToFirstUnread() {
        guard !vmInner.isPerformingScrollToFirstUnread else { return }
        if vmInner.unreadCount == 0 {
            scrollToTop()
            return
        }

        // Walk upward from the post on screen, not from the bottom of the list.
        // After restore, a false appear on a newer row can mark a block as read;
        // the nearest unread above the reading position is still the next tap.
        let startIndex: Int = {
            if let readingID = vmInner.readingPostID ?? vmInner.pendingScrollToPostID,
               let index = posts.firstIndex(where: { $0.id == readingID }) {
                return index
            }
            if let visibleID = layoutStabilizer.visiblePostID(),
               let index = posts.firstIndex(where: { $0.id == visibleID }) {
                return index
            }
            return posts.count
        }()

        if startIndex > 0 {
            var index = startIndex - 1
            while index >= 0 {
                if let unreadCount = vmInner.unreadIds[posts[index].id], unreadCount > 0 {
                    scrollToIndex(index)
                    return
                }
                index -= 1
            }
        }

        for post in posts.reversed() {
            if let unreadCount = vmInner.unreadIds[post.id], unreadCount > 0 {
                if let firstUnreadPostIndex = posts.firstIndex(where: { $0.id == post.id }) {
                    scrollToIndex(firstUnreadPostIndex)

//                    // Regular updateIsAtTop() in onPostAppearOnce { } doesn't catch the first row appearing to set isAtTop to 0, probably because
//                    // .onAppear happens when the offset is closer (like almost appearing), not at 0 when it would be too late for lazy loading
//                    // so force update here after small delay
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
//                        #if DEBUG
//                        L.og.debug("☘️☘️ \(vm.config?.name ?? "?") scrollToFirstUnread -> updateIsAtTop()")
//                        #endif
//                        updateIsAtTop()
//                    }
                }
                break
            }
        }
    }
    
    private func scrollToTop() {
        scrollToIndex(0)
        vmInner.isAtTop = true
        vmInner.readingPostID = nil
        vmInner.holdUnreadAboveReadingPost = false
        markAllAsRead()
//        
//        // Regular updateIsAtTop() in onPostAppearOnce { } doesn't catch the first row appearing to set isAtTop to 0, probably because
//        // .onAppear happens when the offset is closer (like almost appearing), not at 0 when it would be too late for lazy loading
//        // so force update here after small delay
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
//            #if DEBUG
//            L.og.debug("☘️☘️ \(vm.config?.name ?? "?") scrollToFirstUnread -> updateIsAtTop()")
//            #endif
//            updateIsAtTop()
//        }
    }
    
    private func performScrollToIndex(_ scrollToIndex: Int) {
        // While we scroll to previous index here, we are triggering onPostAppearOnce(), which updates markAsRead
        // But it wasn't a real onPostAppearOnce, so we need to avoid that markAsRead. Using isPerformingScroll flag to track that, and prevent re-entrancy.
        if shouldAbortLatePreparedRestore() {
            vmInner.abortPreparedScrollRestore()
            return
        }

        vmInner.isPerformingScroll = true
        
        Task { @MainActor in
            let restorePostID = vmInner.pendingScrollToPostID
            let resolvedScrollToIndex: Int = if let restorePostID,
                                                case .posts(let currentPosts) = vm.viewState,
                                                let currentIndex = currentPosts.firstIndex(where: { $0.id == restorePostID }) {
                currentIndex
            } else {
                scrollToIndex
            }

            let scrollView: UIScrollView? = vm.collectionView ?? vm.tableView
            guard let scrollView, let indexPath = feedIndexPath(for: resolvedScrollToIndex, in: scrollView) else {
                vmInner.isPerformingScroll = false
                vmInner.clearScrollRequest()
                return
            }

            if shouldAbortLatePreparedRestore(in: scrollView) {
                vmInner.isPerformingScroll = false
                vmInner.abortPreparedScrollRestore()
                return
            }
            
            // Disable animations for smoother performance
            UIView.performWithoutAnimation {
                if let collectionView = vm.collectionView {
                    collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
                } else if let tableView = vm.tableView {
                    tableView.scrollToRow(at: indexPath, at: .top, animated: false)
                }
                vmInner.isAtTop = resolvedScrollToIndex == 0
            }

            let rememberedID = restorePostID
                ?? posts[safe: resolvedScrollToIndex]?.id
            if let rememberedID {
                vmInner.readingPostID = rememberedID
                layoutStabilizer.rememberAnchor(id: rememberedID)
                layoutStabilizer.pinItemToVisibleTop(id: rememberedID)
                restoreUnreadIdsAbove(postID: rememberedID)
            }
            
            vmInner.clearScrollRequest()
            vmInner.pendingScrollToPostID = nil
            vmInner.isPreparingForScrollRestore = false
            vmInner.pendingScrollToIndex = nil
            vmInner.scrollRestoreStartedAt = nil

            // This is feed restoration, not unread navigation. Keep the established lightweight
            // path so subsequent new-post insertion can preserve position with withAnimation.
            try? await Task.sleep(nanoseconds: 100_000_000)
            vmInner.isPerformingScroll = false
            vmInner.updateIsAtTopSubject.send()
        }
    }

    private func shouldAbortLatePreparedRestore(in scrollView: UIScrollView? = nil) -> Bool {
        guard vmInner.isPreparingForScrollRestore,
              vmInner.isPreparedScrollRestoreExpired else { return false }
        let scrollView = scrollView ?? vm.collectionView ?? vm.tableView
        guard let scrollView, scrollView.window != nil else { return false }
        return NXFeedViewport.isOffsetAtTop(
            contentOffsetY: scrollView.contentOffset.y,
            insetTop: scrollView.adjustedContentInset.top
        )
    }
    
    private func scrollToIndex(_ scrollToIndex: Int) {
        vmInner.isPerformingScrollToFirstUnread = true
        let targetPost = posts[safe: scrollToIndex]
        if let targetPost {
            layoutStabilizer.rememberAnchor(id: targetPost.id, visibleTopOffset: 0)
            vmInner.readingPostID = targetPost.id
        }

        let scrollView: UIScrollView? = vm.collectionView ?? vm.tableView
        let indexPath = scrollView.flatMap { feedIndexPath(for: scrollToIndex, in: $0) }

        if #available(iOS 16.0, *), let collectionView = vm.collectionView, let indexPath {
            layoutStabilizer.beginProgrammaticScroll()
            collectionView.scrollToItem(at: indexPath, at: .top, animated: true)
            vmInner.isAtTop = scrollToIndex == 0
            finishUnreadScroll(targetPost: targetPost)
        } else if let tableView = vm.tableView, let indexPath {
            layoutStabilizer.beginProgrammaticScroll()
            tableView.scrollToRow(at: indexPath, at: .top, animated: true)
            vmInner.isAtTop = scrollToIndex == 0
            finishUnreadScroll(targetPost: targetPost)
        } else {
            vmInner.isPerformingScrollToFirstUnread = false
            layoutStabilizer.cancelProgrammaticScroll()
        }
    }

    private func restoreUnreadIdsAbove(postID: String) {
        guard case .posts(let currentPosts) = vm.viewState,
              let restoreIndex = currentPosts.firstIndex(where: { $0.id == postID }) else { return }
        vmInner.updateUnreadIds { unreadIds in
            for index in currentPosts.indices where index < restoreIndex {
                let post = currentPosts[index]
                if unreadIds[post.id] == nil || unreadIds[post.id] == 0 {
                    unreadIds[post.id] = 1 + post.parentPosts.count
                }
            }
        }
    }

    private func feedIndexPath(for itemIndex: Int, in scrollView: UIScrollView) -> IndexPath? {
        NXFeedIndexMapping.indexPath(
            forItemIndex: itemIndex,
            sectionCounts: {
                if let collectionView = scrollView as? UICollectionView {
                    return (0..<collectionView.numberOfSections).map { collectionView.numberOfItems(inSection: $0) }
                }
                if let tableView = scrollView as? UITableView {
                    return (0..<tableView.numberOfSections).map { tableView.numberOfRows(inSection: $0) }
                }
                return []
            }(),
            itemCount: posts.count
        )
    }

    private func finishUnreadScroll(targetPost: NRPost?) {
        Task { @MainActor in
            // Animated scroll duration varies with distance. Wait for UIKit to actually finish,
            // then correct once after any self-sizing rows encountered along the way have laid out.
            var previousOffset: CGFloat?
            var stableSamples = 0
            for _ in 0..<40 {
                let scrollView: UIScrollView? = vm.collectionView ?? vm.tableView
                guard let scrollView else { break }
                let currentOffset = scrollView.contentOffset.y
                if let previousOffset, abs(previousOffset - currentOffset) < 0.5,
                   !scrollView.isDragging, !scrollView.isDecelerating, !scrollView.isTracking {
                    stableSamples += 1
                } else {
                    stableSamples = 0
                }
                previousOffset = currentOffset

                // Programmatic animated scrolling does not consistently set isDecelerating.
                // Requiring several stable presentation samples avoids interrupting its animation.
                if stableSamples >= 3 {
                    await layoutStabilizer.finishProgrammaticScroll {
                        if let id = targetPost?.id {
                            layoutStabilizer.pinItemToVisibleTop(id: id)
                        }
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if layoutStabilizer.isProgrammaticScrollPending {
                await layoutStabilizer.finishProgrammaticScroll {
                    if let id = targetPost?.id {
                        layoutStabilizer.pinItemToVisibleTop(id: id)
                    }
                }
            }
            if let targetPost {
                // Do not depend on onAppear here: List may reuse an already-visible row and never
                // fire it again. Consume exactly the post selected by the unread index at tap time.
                performIDCollectionUpdates(for: targetPost, vm: vm)
                performUnreadMarkingUpdates(for: targetPost, vm: vm)
            }
            vmInner.isPerformingScrollToFirstUnread = false
            vmInner.updateIsAtTopSubject.send()
        }
    }

    private func restorePreparedScrollPositionIfNeeded(in scrollView: UIScrollView) {
        guard vmInner.isPreparingForScrollRestore else { return }
        if shouldAbortLatePreparedRestore(in: scrollView) {
            vmInner.abortPreparedScrollRestore()
            return
        }
        let restorePostID = vmInner.pendingScrollToPostID ?? vmInner.readingPostID
        let restoreIndex = restorePostID.flatMap { postID in posts.firstIndex(where: { $0.id == postID }) }
            ?? vmInner.pendingScrollToIndex
        guard let restoreIndex, restoreIndex > 0 else { return }

        let sectionCounts: [Int]
        if let collectionView = scrollView as? UICollectionView {
            sectionCounts = (0..<collectionView.numberOfSections).map { collectionView.numberOfItems(inSection: $0) }
        } else if let tableView = scrollView as? UITableView {
            sectionCounts = (0..<tableView.numberOfSections).map { tableView.numberOfRows(inSection: $0) }
        } else {
            return
        }
        guard let indexPath = NXFeedIndexMapping.indexPath(
            forItemIndex: restoreIndex,
            sectionCounts: sectionCounts,
            itemCount: posts.count
        ) else { return }

        UIView.setAnimationsEnabled(false)
        if let collectionView = scrollView as? UICollectionView {
            collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
        } else if let tableView = scrollView as? UITableView {
            tableView.scrollToRow(at: indexPath, at: .top, animated: false)
        }
        UIView.setAnimationsEnabled(true)

        if let restorePostID {
            vmInner.readingPostID = restorePostID
            layoutStabilizer.rememberAnchor(id: restorePostID)
        }
        vmInner.isAtTop = false
        vmInner.updateIsAtTopSubject.send()
    }

    private func _updateIsAtTop() {
        guard !vmInner.isPerformingScroll else { return }

        // The ScrollOffset proxy reports 0 when it has no subscription, which looks like
        // "at top" and used to send a restored feed into the prepend-at-top path.
        let scrollView: UIScrollView? = vm.collectionView ?? vm.tableView
        guard let scrollView else { return }

        let isAtTopNow = NXFeedViewport.isOffsetAtTop(
            contentOffsetY: scrollView.contentOffset.y,
            insetTop: scrollView.adjustedContentInset.top
        )

        // Status-bar tap-to-top never goes through scrollToTop(). Detect it from
        // the live offset and clear unread even if isAtTop was already true.
        if isAtTopNow && !vmInner.isPreparingForScrollRestore {
            vmInner.readingPostID = nil
            vmInner.holdUnreadAboveReadingPost = false
            markAllAsRead()
        }

        guard !vmInner.isPreparingForScrollRestore else { return }
        
        // Only update if the state actually changed
        guard vmInner.isAtTop != isAtTopNow else { return }
        
        vmInner.isAtTop = isAtTopNow
        
#if DEBUG
        L.og.debug("☘️☘️ \(vm.config?.name ?? "?") contentOffset.y: \(scrollView.contentOffset.y) isAtTop: \(isAtTopNow) -[LOG]-")
#endif
    }

    private func onPostDisappear(_ nrPost: NRPost) {
        // Only trigger updateIsAtTop if we're not performing programmatic scrolls
        guard !vmInner.isPerformingScroll && !vmInner.isPerformingScrollToFirstUnread else { return }
        
#if DEBUG
        L.og.debug("☘️☘️ \(vm.config?.name ?? "?") NXPostsFeed.onPostDisappear() -> updateIsAtTop() BEFORE: \(vmInner.isAtTop) -[LOG]-")
#endif
        vmInner.updateIsAtTopSubject.send()
    }
    
    private func markAllAsRead() {
        if !vmInner.unreadIds.isEmpty {
#if DEBUG
            L.og.debug("☘️☘️ \(vm.config?.name ?? "?") NXPostsFeed.markAllAsRead() -[LOG]-")
#endif
            vmInner.unreadIds = [:]
        }
    }
}



func performIDCollectionUpdates(for nrPost: NRPost, vm: NXColumnViewModel) {
    if nrPost.postOrThreadAttributes.parentPosts.isEmpty {
        if nrPost.kind == 6, let firstQuoteId = nrPost.firstQuoteId {
            vm.markShortIdsSeen([nrPost.shortId, String(firstQuoteId.prefix(8))])
        }
        else {
            vm.markShortIdSeen(nrPost.shortId)
        }
    }
    else {
        let leafIds: Set<String> = Set(nrPost.postOrThreadAttributes.parentPosts.map { $0.shortId } + [nrPost.shortId])
        vm.markShortIdsSeen(leafIds)
    }
}

@MainActor
func performUnreadMarkingUpdates(for nrPost: NRPost, vm: NXColumnViewModel) {
    let vmInner = vm.vmInner
    vm.newestMarkedAsRead = max(nrPost.createdAt, vm.newestMarkedAsRead ?? .distantPast)
    // Early exit if no unread items to process
    guard vmInner.unreadIds[nrPost.id] != 0 else { return }
    
    // Batch unread ID updates
    var idsToMarkAsRead: [String] = []
    var notificationPairs: [(String, UUID)] = []
    
    vmInner.updateUnreadIds { unreadIds in
        // Current post
        unreadIds[nrPost.id] = 0
        idsToMarkAsRead.append(nrPost.shortId)
        notificationPairs.append((nrPost.id, vm.columnVMid))

        // Quote posts
        if nrPost.kind == 6, let firstQuoteId = nrPost.firstQuoteId {
            let shortQuoteId = String(firstQuoteId.prefix(8))
            idsToMarkAsRead.append(shortQuoteId)
            notificationPairs.append((firstQuoteId, vm.columnVMid))
        }

        // Parent posts
        if !nrPost.parentPosts.isEmpty {
            let parentShortIds = nrPost.parentPosts.map { $0.shortId }
            idsToMarkAsRead.append(contentsOf: parentShortIds)
            notificationPairs.append(contentsOf: nrPost.parentPosts.map { ($0.id, vm.columnVMid) })
        }

        // Mark remaining posts in feed as read (optimize this heavy operation)
        if let appearedIndex = vm.currentNRPostsOnScreen.firstIndex(where: { $0.id == nrPost.id }) {
            for i in appearedIndex..<vm.currentNRPostsOnScreen.count {
                if unreadIds[vm.currentNRPostsOnScreen[i].id] != 0 {
                    unreadIds[vm.currentNRPostsOnScreen[i].id] = 0
                    idsToMarkAsRead.append(vm.currentNRPostsOnScreen[i].shortId)

                    if vm.currentNRPostsOnScreen[i].isRepost, let firstQuoteId = vm.currentNRPostsOnScreen[i].firstQuoteId {
                        idsToMarkAsRead.append(String(firstQuoteId.prefix(8)))
                    }

                    if !vm.currentNRPostsOnScreen[i].parentPosts.isEmpty {
                        idsToMarkAsRead.append(contentsOf: vm.currentNRPostsOnScreen[i].parentPosts.map { $0.shortId })
                    }
                }
            }
        }
    }
    
    vm.markAsRead(idsToMarkAsRead)
    
    for (id, columnId) in notificationPairs {
        FeedsCoordinator.shared.markedAsReadSubject.send((id, columnId))
    }
    
    // Update UI immediately for responsiveness
    vmInner.updateIsAtTopSubject.send()
}
