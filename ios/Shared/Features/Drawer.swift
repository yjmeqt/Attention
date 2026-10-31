import SwiftUI
import UIKit

/// A side panel under the content, which slides right to reveal it. A horizontal swipe anywhere on the content
/// opens it; a swipe back, a tap on the dimmed content or `isOpen = false` closes it.
struct Drawer<Panel: View, Content: View>: View {
    @Binding var isOpen: Bool
    /// Off while something else owns horizontal swipes, such as the back swipe of a pushed page.
    var isEnabled = true
    @ViewBuilder var panel: Panel
    @ViewBuilder var content: Content

    /// How far the current swipe has moved the content from where `isOpen` puts it.
    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width * 0.82, 320)
            let offset = min(max((isOpen ? width : 0) + drag, 0), width)
            let progress = offset / width
            ZStack(alignment: .leading) {
                // Only there while showing: hiding it isn't enough to keep VoiceOver out of its scroll view.
                if progress > 0 {
                    panel
                        .frame(width: width)
                        .offset(x: (progress - 1) * width * 0.25)
                        .allowsHitTesting(isOpen)
                        .accessibilityElement(children: .contain)
                        .accessibilityAddTraits(isOpen ? .isModal : [])
                        .accessibilityAction(.escape) { close() }
                }

                content
                    .background(Color(.systemBackground))
                    .overlay {
                        Color.black.opacity(0.25 * progress)
                            .ignoresSafeArea()
                            .allowsHitTesting(isOpen)
                            .onTapGesture { close() }
                            .accessibilityHidden(true)
                    }
                    .offset(x: offset)
                    .accessibilityHidden(isOpen)
            }
            .gesture(DrawerPan(isOpen: isOpen, isEnabled: isEnabled || isOpen) { phase in
                switch phase {
                case let .changed(translation):
                    drag = translation
                case let .ended(translation, velocity):
                    let projected = (isOpen ? width : 0) + translation + velocity * 0.2
                    withAnimation(.snappy(duration: 0.3)) {
                        isOpen = projected > width / 2
                        drag = 0
                    }
                }
            })
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isOpen) { _, open in open }
        .onChange(of: isEnabled) { _, enabled in if !enabled { close() } }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.3)) { isOpen = false }
    }
}

/// A horizontal pan that starts only when the swipe is mostly sideways and heads the way the drawer can move,
/// and not while a list under the finger is still coasting. It takes over from that list's scrolling once it starts.
private struct DrawerPan: UIGestureRecognizerRepresentable {
    enum Phase {
        case changed(CGFloat)
        case ended(CGFloat, velocity: CGFloat)
    }

    let isOpen: Bool
    let isEnabled: Bool
    let onChange: (Phase) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context: Context) {
        pan.isEnabled = isEnabled
        context.coordinator.isOpen = isOpen
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let translation = pan.translation(in: pan.view).x
        switch pan.state {
        case .began:
            context.coordinator.stopScrolling()
            onChange(.changed(translation))
        case .changed:
            onChange(.changed(translation))
        case .ended, .cancelled, .failed:
            onChange(.ended(pan.state == .ended ? translation : 0, velocity: pan.velocity(in: pan.view).x))
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isOpen = false
        private weak var scrollView: UIScrollView?

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }
            let velocity = pan.velocity(in: view)
            guard abs(velocity.x) > abs(velocity.y) * 1.5, isOpen ? velocity.x < 0 : velocity.x > 0 else { return false }
            scrollView = Self.scrollView(at: pan.location(in: view), in: view)
            return scrollView?.isDecelerating != true
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }

        /// Ends the scroll the finger started along with the swipe, so the list doesn't move with the drawer.
        func stopScrolling() {
            guard let pan = scrollView?.panGestureRecognizer else { return }
            pan.isEnabled = false
            pan.isEnabled = true
        }

        private static func scrollView(at point: CGPoint, in view: UIView) -> UIScrollView? {
            var hit = view.hitTest(point, with: nil)
            while let current = hit {
                if let scrollView = current as? UIScrollView { return scrollView }
                hit = current.superview
            }
            return nil
        }
    }
}
