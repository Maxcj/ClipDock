//
//  ClipboardPreviewSupport.swift
//  ClipDock
//

import SwiftUI
import AppKit

struct AsyncDetailImageView: View {
    @Environment(\.appLocalizer) private var localizer
    let imagePath: String?
    let initialImage: NSImage?
    let placeholderTitle: String
    let maxPixelSize: CGFloat
    let cornerRadius: CGFloat
    let height: CGFloat? = nil
    let fallbackHeight: CGFloat

    @State private var image: NSImage?
    @State private var originalImage: NSImage?
    @State private var isLoading = false
    @State private var isHovering = false
    @State private var requestToken = UUID()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            previewSurface

            if previewImageForPresentation != nil {
                Button {
                    presentPreviewPanel()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                        Text(localizer.text(.previewImage))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .foregroundStyle(.primary)
                    .background(Color.white.opacity(isHovering ? 0.96 : 0.88))
                    .clipShape(Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .padding(12)
                .opacity(isHovering ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
                .accessibilityLabel(localizer.text(.previewImage))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height ?? fallbackHeight)
        .onHover { hovering in
            isHovering = hovering
        }
        .task(id: imagePath) {
            image = nil
            originalImage = nil

            if let initialImage {
                image = initialImage
                originalImage = initialImage
            }

            let token = UUID()
            requestToken = token

            guard let imagePath, !imagePath.isEmpty else {
                return
            }

            isLoading = true
            defer { isLoading = false }

            let loadedImages = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    let original = ClipboardImageCache.shared.image(at: imagePath)
                    let preview = ClipboardImageCache.shared.downsampledImage(at: imagePath, maxPixelSize: maxPixelSize)
                    return (preview, original)
                }
            }.value

            guard !Task.isCancelled else { return }
            guard token == requestToken else { return }
            image = loadedImages.0 ?? loadedImages.1 ?? initialImage
            originalImage = loadedImages.1 ?? initialImage
        }
    }

    private var previewImageForPresentation: NSImage? {
        originalImage ?? image ?? initialImage
    }

    private func presentPreviewPanel() {
        guard let previewImage = previewImageForPresentation else { return }
        ImagePreviewPanelController.shared.present(image: previewImage)
    }

    private var previewSurface: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let initialImage {
                Image(nsImage: initialImage)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height ?? fallbackHeight)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.16))
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: isLoading ? "hourglass" : "photo")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.65))

            Text(placeholderTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.94),
                    Color(red: 0.89, green: 0.94, blue: 1.0).opacity(0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

final class ImagePreviewPanelController: NSObject {
    static let shared = ImagePreviewPanelController()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<ImagePreviewPanelContent>?

    func present(image: NSImage) {
        if let panel, let hostingController {
            hostingController.rootView = ImagePreviewPanelContent(
                image: image,
                onClose: { [weak self] in self?.dismiss() }
            )
            panel.setContentSize(Self.contentSize(for: image))
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = ImagePreviewPanelContent(image: image, onClose: { [weak self] in self?.dismiss() })
        let hostingController = NSHostingController(rootView: rootView)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize(for: image)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.hidesOnDeactivate = false
        panel.center()
        panel.delegate = self
        self.hostingController = hostingController
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
    }

    private static func contentSize(for image: NSImage) -> NSSize {
        let imageWidth = max(1, image.size.width)
        let imageHeight = max(1, image.size.height)
        return NSSize(width: imageWidth, height: imageHeight)
    }
}

extension ImagePreviewPanelController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        panel = nil
        hostingController = nil
    }
}

struct ImagePreviewPanelContent: View {
    let image: NSImage
    let onClose: () -> Void

    var body: some View {
        Image(nsImage: image)
            .interpolation(.high)
            .resizable()
            .scaledToFit()
            .frame(width: max(1, image.size.width), height: max(1, image.size.height))
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(Color.black.opacity(0.55))
                .foregroundStyle(.white)
                .clipShape(Circle())
                .padding(12)
            }
            .background(Color.black.opacity(0.92))
    }
}

struct FileDetailPreview: View {
    @Environment(\.appLocalizer) private var localizer
    let record: ClipboardRecord
    let subtitleFontSize: CGFloat
    let footerFontSize: CGFloat
    let iconSize: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 18) {
            fileIcon
                .frame(width: max(120, iconSize + 24), height: height)

            VStack(alignment: .leading, spacing: 10) {
                Text(record.previewTitle)
                    .font(.system(size: 28, weight: .semibold))
                    .lineLimit(3)

                Text(record.fileSubtitleText)
                    .font(.system(size: subtitleFontSize))
                    .foregroundStyle(.secondary)

                if record.kind == .files {
                    Text(record.fileSizeLabel)
                        .font(.system(size: footerFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .frame(height: height, alignment: .center)
    }

    @ViewBuilder
    private var fileIcon: some View {
        if let icon = record.fileIconImage {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
            }
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(record.kind.accent.opacity(0.12))
                .overlay(
                    Image(systemName: "doc")
                        .font(.system(size: iconSize * 0.38, weight: .regular))
                        .foregroundStyle(record.kind.accent)
                )
        }
    }
}

struct LinkDetailPreview: View {
    let record: ClipboardRecord
    let subtitleFontSize: CGFloat
    let footerFontSize: CGFloat
    let iconSize: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 18) {
            websiteIcon
                .frame(width: max(120, iconSize + 24), height: height)

            VStack(alignment: .leading, spacing: 10) {
                Text(record.rowSubtitle)
                    .font(.system(size: 28, weight: .semibold))
                    .lineLimit(3)

                Text(record.previewTitle)
                    .font(.system(size: subtitleFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Text(record.previewSubtitle)
                    .font(.system(size: footerFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .frame(height: height, alignment: .center)
    }

    @ViewBuilder
    private var websiteIcon: some View {
        if let icon = record.websiteIconImage {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
            }
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(record.kind.accent.opacity(0.12))
                .overlay(
                    Image(systemName: "globe")
                        .font(.system(size: iconSize * 0.38, weight: .regular))
                        .foregroundStyle(record.kind.accent)
                )
        }
    }
}
