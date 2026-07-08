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

            if let initialImage {
                image = initialImage
            }

            let token = UUID()
            requestToken = token

            guard let imagePath, !imagePath.isEmpty else {
                return
            }

            isLoading = true
            defer { isLoading = false }

            let previewImage = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    ClipboardImageCache.shared.downsampledImage(at: imagePath, maxPixelSize: maxPixelSize)
                }
            }.value

            guard !Task.isCancelled else { return }
            guard token == requestToken else { return }
            image = previewImage ?? initialImage
        }
    }

    private var previewImageForPresentation: NSImage? {
        image ?? initialImage
    }

    private func presentPreviewPanel() {
        guard let imagePath, !imagePath.isEmpty else {
            if let previewImage = previewImageForPresentation {
                ImagePreviewPanelController.shared.present(image: previewImage)
            }
            return
        }

        Task.detached(priority: .userInitiated) {
            let originalImage = ClipboardImageCache.shared.image(at: imagePath)
            await MainActor.run {
                if let originalImage {
                    ImagePreviewPanelController.shared.present(image: originalImage)
                }
            }
        }
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
        let screenFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxWidth = screenFrame.width * 0.82
        let maxHeight = screenFrame.height * 0.82
        let imageWidth = max(1, image.size.width)
        let imageHeight = max(1, image.size.height)
        let scale = min(maxWidth / imageWidth, maxHeight / imageHeight, 1)
        return NSSize(width: imageWidth * scale, height: imageHeight * scale)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    let status: ClipboardFileStatus?
    let isLoading: Bool
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

                Text(subtitleText)
                    .font(.system(size: subtitleFontSize))
                    .foregroundStyle(.secondary)

                if record.kind == .files {
                    Text(fileSizeText)
                        .font(.system(size: footerFontSize, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(record.fileCacheStatusText)
                        .font(.system(size: footerFontSize, weight: .medium))
                        .foregroundStyle(record.fileCacheStatusTint)
                }

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .frame(height: height, alignment: .center)
    }

    private var subtitleText: String {
        if let status {
            if !status.displayPathText.isEmpty {
                return status.displayPathText
            }
            return status.originalStatusText(localizer: localizer)
        }

        return isLoading ? "Checking file status..." : "-"
    }

    private var fileSizeText: String {
        if let status {
            return status.fileSizeLabel
        }

        return isLoading ? "..." : "-"
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

private extension ClipboardFileStatus {
    func originalStatusText(localizer: AppLocalizer) -> String {
        switch originalStatus {
        case .noOriginalPath:
            return localizer.text(.pathOnlyNoCachedCopy)
        case .available:
            return localizer.text(.originalFileAvailable)
        case .missingUsingCachedCopy:
            return localizer.text(.originalFileMissingUsingCachedCopy)
        case .missing:
            return localizer.text(.originalFileMissing)
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
