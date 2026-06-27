//
//  ClipboardPreviewSupport.swift
//  ClipDock
//

import SwiftUI
import AppKit

struct AsyncDetailImageView: View {
    let imagePath: String?
    let placeholderTitle: String
    let maxPixelSize: CGFloat
    let cornerRadius: CGFloat
    let height: CGFloat? = nil
    let fallbackHeight: CGFloat

    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var requestToken = UUID()

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
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
        .task(id: imagePath) {
            image = nil

            let token = UUID()
            requestToken = token

            guard let imagePath, !imagePath.isEmpty else {
                return
            }

            isLoading = true
            defer { isLoading = false }

            let loadedImage = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    ClipboardImageCache.shared.downsampledImage(at: imagePath, maxPixelSize: maxPixelSize)
                }
            }.value

            guard !Task.isCancelled else { return }
            guard token == requestToken else { return }
            image = loadedImage
        }
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

                Text(record.fileStatusText)
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
