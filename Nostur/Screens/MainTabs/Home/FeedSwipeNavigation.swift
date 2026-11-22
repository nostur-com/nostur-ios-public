import SwiftUI
import UIKit

struct FeedSwipeSelection: Equatable, Identifiable {
    let tab: String
    var listId: String? = nil

    var id: String { "\(tab):\(listId ?? "")" }

    func adjacent(in feeds: [Self], offset: Int) -> Self? {
        guard offset == 1 || offset == -1, let index = feeds.firstIndex(of: self),
              feeds.indices.contains(index + offset) else { return nil }
        return feeds[index + offset]
    }
}

/// Kept in @State by the screen, and observed only by the paging modifiers.
/// Dragging must not rebuild the feed screen or change column visibility.
@MainActor
final class FeedSwipeMotion: ObservableObject {
    @Published var translation: CGFloat = 0
}

struct FeedPagePosition: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let relativeIndex: Int
    @ObservedObject var motion: FeedSwipeMotion

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(theme.listBackground)
                .offset(x: UIDevice.current.userInterfaceIdiom == .phone
                        ? CGFloat(relativeIndex) * geometry.size.width + motion.translation : 0)
        }
        .opacity(UIDevice.current.userInterfaceIdiom == .phone
                 ? (abs(relativeIndex) <= 1 ? 1 : 0) : (relativeIndex == 0 ? 1 : 0))
        .allowsHitTesting(relativeIndex == 0)
        .accessibilityHidden(relativeIndex != 0)
        .transaction { if reduceMotion { $0.animation = nil } }
    }
}

struct FeedSwipeModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var motion: FeedSwipeMotion
    let isEnabled: Bool
    let canSwipe: (Int) -> Bool
    let onSwipe: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .background {
                FeedPanAttachment(isEnabled: isEnabled, onChanged: dragChanged,
                                  onEnded: { translation, velocity, width, cancelled in
                    dragEnded(translation: translation, velocity: velocity,
                              width: width, cancelled: cancelled)
                })
                .allowsHitTesting(false)
            }
        .clipped()
        .onDisappear { motion.translation = 0 }
    }

    private func dragChanged(_ translation: CGFloat) {
        let direction = translation < 0 ? 1 : -1
        motion.translation = canSwipe(direction) ? translation : translation * 0.18
    }

    private func dragEnded(translation: CGFloat, velocity: CGFloat, width: CGFloat, cancelled: Bool) {
        let direction = FeedPanGesturePolicy.destination(translation: translation, velocity: velocity,
                                                        width: width, cancelled: cancelled)
        withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .interactiveSpring(response: 0.32, dampingFraction: 1)) {
            motion.translation = 0
            if let direction, canSwipe(direction) { onSwipe(direction) }
        }
    }
}

struct FeedPanGesturePolicy {
    static func isHorizontal(_ velocity: CGPoint) -> Bool {
        abs(velocity.x) > abs(velocity.y) * 1.5
    }

    static func destination(translation: CGFloat, velocity: CGFloat, width: CGFloat, cancelled: Bool) -> Int? {
        guard !cancelled, width > 0 else { return nil }
        let isFlick = abs(translation) > 18 && abs(velocity) > 650 && translation * velocity > 0
        guard abs(translation) > min(width * 0.22, 90) || isFlick else { return nil }
        return translation < 0 ? 1 : -1
    }

    @MainActor
    static func allowsTouch(in touchedView: UIView?, upTo host: UIView?) -> Bool {
        var view = touchedView
        while let candidate = view {
            // A post may itself be backed by a control. Only controls whose
            // horizontal interaction edits a value should exclude feed paging.
            if candidate is UISlider || candidate is UISwitch || candidate is UITextField { return false }
            if let text = candidate as? UITextView, text.selectedRange.length > 0 { return false }
            if let scroll = candidate as? UIScrollView, scroll.isScrollEnabled,
               scroll.alwaysBounceHorizontal || scroll.contentSize.width > scroll.bounds.width + 8 { return false }
            if candidate === host { break }
            view = candidate.superview
        }
        return true
    }
}

/// Attach to the actual UIKit ancestor of the feed's native List/text views.
/// The marker scopes touches to the feed viewport, including native post text.
struct FeedPanAttachment: UIViewRepresentable {
    let isEnabled: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat, CGFloat, Bool) -> Void

    func makeUIView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: MarkerView, context: Context) {
        if context.coordinator.pan.isEnabled != isEnabled {
            context.coordinator.pan.isEnabled = isEnabled
        }
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.attach(to: view)
    }

    static func dismantleUIView(_ view: MarkerView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class MarkerView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { coordinator?.detach() }
            else { coordinator?.attach(to: self) }
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            if window != nil { coordinator?.attach(to: self) }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat, CGFloat, CGFloat, Bool) -> Void = { _, _, _, _ in }
        private weak var marker: MarkerView?
        private var touchStartedAt: TimeInterval = 0
        private var startX: CGFloat = 0
        private(set) lazy var pan: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.maximumNumberOfTouches = 1
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        func attach(to marker: MarkerView) {
            self.marker = marker
            guard marker.window != nil, UIDevice.current.userInterfaceIdiom == .phone else { return }
            // SwiftUI inserts responders (such as its key-press responder)
            // between the hosting view and controller. Follow the full responder
            // chain rather than assuming hostingView.next is the controller.
            var responder: UIResponder? = marker
            while let current = responder {
                if let controller = current as? UIViewController, let host = controller.viewIfLoaded {
                    if pan.view !== host {
                        pan.view?.removeGestureRecognizer(pan)
                        host.addGestureRecognizer(pan)
                    }
                    return
                }
                responder = current.next
            }
        }

        func detach() {
            pan.view?.removeGestureRecognizer(pan)
            marker = nil
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: nil).x
            switch recognizer.state {
            case .began, .changed: onChanged(translation)
            case .ended: onEnded(translation, recognizer.velocity(in: nil).x, marker?.bounds.width ?? 0, false)
            case .cancelled, .failed: onEnded(translation, 0, marker?.bounds.width ?? 0, true)
            default: break
            }
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let marker, let host = recognizer.view, let touchedView = touch.view,
                  touchedView.isDescendant(of: host),
                  marker.bounds.contains(touch.location(in: marker)) else { return false }
            touchStartedAt = touch.timestamp
            startX = touch.location(in: marker).x
            return FeedPanGesturePolicy.allowsTouch(in: touchedView, upTo: host)
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let marker, let pan = recognizer as? UIPanGestureRecognizer,
                  FeedPanGesturePolicy.isHorizontal(pan.velocity(in: nil)),
                  startX > 24, startX < marker.bounds.width - 24 else { return false }
            // A held finger belongs to text selection or a context menu.
            return ProcessInfo.processInfo.systemUptime - touchStartedAt < 0.45
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // SwiftUI and UITextView also own recognizers on plain UIViews.
            // Axis, edge, long-press, and nested-media checks happen above.
            true
        }
    }
}
