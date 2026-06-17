import AppKit
import SwiftUI

extension View {
    func hiddenScrollIndicators() -> some View {
        scrollIndicators(.hidden)
            .background(
                HiddenScrollIndicatorConfigurator()
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            )
    }
}

struct HiddenScrollIndicatorConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleConfiguration(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleConfiguration(from: nsView)
    }

    private func scheduleConfiguration(from view: NSView) {
        DispatchQueue.main.async {
            configureScrollViews(near: view)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            configureScrollViews(near: view)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            configureScrollViews(near: view)
        }
    }

    private func configureScrollViews(near view: NSView) {
        if let root = view.window?.contentView {
            configureScrollViews(in: root)
            return
        }

        var current: NSView? = view
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView ?? candidate.enclosingScrollView {
                configure(scrollView)
            }

            current = candidate.superview
        }
    }

    private func configureScrollViews(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            configure(scrollView)
        }

        view.subviews.forEach(configureScrollViews(in:))
    }

    private func configure(_ scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScroller = nil
        scrollView.horizontalScroller = nil
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.postsBoundsChangedNotifications = true
    }
}
