//
//  WindowSupport.swift
//  ClipDock
//

import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        ResolvingView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let resolvingView = nsView as? ResolvingView {
            resolvingView.onResolve = onResolve
        }
    }

    final class ResolvingView: NSView {
        var onResolve: ((NSWindow) -> Void)?

        init(onResolve: @escaping (NSWindow) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                DispatchQueue.main.async { [weak self] in
                    self?.onResolve?(window)
                }
            }
        }
    }
}

struct KeyCommandInterceptor: NSViewRepresentable {
    let isSearchFocused: Bool
    let onUp: () -> Void
    let onDown: () -> Void
    let onLeft: () -> Void
    let onRight: () -> Void

    func makeNSView(context: Context) -> NSView {
        InterceptView(
            isSearchFocused: isSearchFocused,
            onUp: onUp,
            onDown: onDown,
            onLeft: onLeft,
            onRight: onRight
        )
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let interceptView = nsView as? InterceptView else { return }
        interceptView.isSearchFocused = isSearchFocused
        interceptView.onUp = onUp
        interceptView.onDown = onDown
        interceptView.onLeft = onLeft
        interceptView.onRight = onRight
    }

    final class InterceptView: NSView {
        var isSearchFocused: Bool
        var onUp: () -> Void
        var onDown: () -> Void
        var onLeft: () -> Void
        var onRight: () -> Void
        private var monitor: Any?

        init(
            isSearchFocused: Bool,
            onUp: @escaping () -> Void,
            onDown: @escaping () -> Void,
            onLeft: @escaping () -> Void,
            onRight: @escaping () -> Void
        ) {
            self.isSearchFocused = isSearchFocused
            self.onUp = onUp
            self.onDown = onDown
            self.onLeft = onLeft
            self.onRight = onRight
            super.init(frame: .zero)
            installMonitor()
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func installMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
                    return event
                }

                if self.isSearchFocused {
                    return event
                }

                switch event.keyCode {
                case 126:
                    self.onUp()
                    return nil
                case 125:
                    self.onDown()
                    return nil
                case 123:
                    self.onLeft()
                    return nil
                case 124:
                    self.onRight()
                    return nil
                default:
                    return event
                }
            }
        }
    }
}
