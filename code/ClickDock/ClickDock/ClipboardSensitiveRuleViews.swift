//
//  ClipboardSensitiveRuleViews.swift
//  ClipDock
//

import SwiftUI
import AppKit

struct ClipboardSensitiveRuleRow: View {
    @Binding var rule: ClipboardSensitiveRule

    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void

    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(rule.matchType == .regex ? Color(red: 0.60, green: 0.35, blue: 0.95).opacity(0.14) : Color.accentColor.opacity(0.14))

                Image(systemName: rule.matchType == .regex ? "text.badge.checkmark" : "text.cursor")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(rule.matchType == .regex ? Color(red: 0.60, green: 0.35, blue: 0.95) : Color.accentColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(rule.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                        .lineLimit(1)

                    if !rule.isEnabled {
                        Text(localizer.text(.hidden))
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.04))
                            .clipShape(Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(rule.pattern)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    ClipboardSensitiveRuleChip(title: rule.matchType.title)
                    if rule.matchType == .keyword {
                        ClipboardSensitiveRuleChip(title: rule.keywordMatchMode.title)
                    }
                    ClipboardSensitiveRuleChip(title: rule.scope.title)
                    if rule.isCaseSensitive {
                        ClipboardSensitiveRuleChip(title: localizer.text(.caseSensitive))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .top, spacing: 8) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(ClipboardSensitiveRuleIconButtonStyle(kind: .accent))

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(ClipboardSensitiveRuleIconButtonStyle(kind: .destructive))

                Toggle("", isOn: $rule.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .padding(.top, 1)
                    .onChange(of: rule.isEnabled) { _ in
                        onToggle()
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct ClipboardSensitiveRuleIconButtonStyle: ButtonStyle {
    enum Kind {
        case accent
        case destructive
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        let tint: Color = {
            switch kind {
            case .accent:
                return Color.accentColor
            case .destructive:
                return Color(red: 0.96, green: 0.27, blue: 0.22)
            }
        }()

        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 26, height: 26)
            .foregroundStyle(tint)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.18 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(configuration.isPressed ? 0.06 : 0.12), lineWidth: 1)
            )
    }
}

struct ClipboardSensitiveRulePrimaryButtonStyle: ButtonStyle {
    enum Kind {
        case neutral
        case accent
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        let foreground: Color = kind == .neutral ? .primary : .white
        let background: Color = kind == .neutral
            ? Color.white.opacity(configuration.isPressed ? 0.56 : 0.80)
            : Color.accentColor.opacity(configuration.isPressed ? 0.82 : 1.0)
        let borderOpacity: Double = kind == .accent ? 0.0 : 0.08
        let shadowColor: Color = kind == .accent ? Color.accentColor.opacity(0.16) : .clear
        let shadowRadius: CGFloat = kind == .accent ? 8 : 0
        let shadowYOffset: CGFloat = kind == .accent ? 3 : 0

        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 30)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(borderOpacity), lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
    }
}

struct ClipboardSensitiveRuleChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.04))
            .clipShape(Capsule())
            .foregroundStyle(.secondary)
    }
}

struct ClipboardSensitiveRuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLocalizer) private var localizer

    let rule: ClipboardSensitiveRule?
    let onSave: (ClipboardSensitiveRule) -> Void

    @State private var name = ""
    @State private var matchType: ClipboardSensitiveRuleMatchType = .keyword
    @State private var keywordMatchMode: ClipboardSensitiveRuleKeywordMatchMode = .contains
    @State private var pattern = ""
    @State private var scope: ClipboardSensitiveRuleScope = .all
    @State private var isCaseSensitive = false
    @State private var isEnabled = true
    @State private var regexError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            editorHeader

            VStack(spacing: 14) {
                editorCard(
                    title: localizer.text(.ruleName),
                    subtitle: localizer.text(.ruleNameSubtitle),
                    leadingIcon: "tag.fill"
                ) {
                    TextField(localizer.text(.ruleNamePlaceholder), text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                editorCard(
                    title: localizer.text(.matchType),
                    subtitle: localizer.text(.matchTypeSubtitle),
                    leadingIcon: matchType == .regex ? "text.badge.checkmark" : "text.cursor"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("", selection: $matchType) {
                            ForEach(ClipboardSensitiveRuleMatchType.allCases) { type in
                                Text(type.title).tag(type)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(localizer.text(.rulePattern))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)

                            TextField(patternPlaceholder, text: $pattern)
                                .font(.system(size: 12, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: pattern) { _ in
                                    validatePattern()
                                }

                            Text(patternSubtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        if matchType == .keyword {
                            Divider()

                            VStack(alignment: .leading, spacing: 6) {
                                Text(localizer.text(.keywordMatchMode))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                Picker("", selection: $keywordMatchMode) {
                                    ForEach(ClipboardSensitiveRuleKeywordMatchMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)

                                Text(localizer.text(.keywordMatchModeSubtitle))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let regexError {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.red)
                                    .padding(.top, 1)

                                Text(regexError)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 0)
                            }
                            .padding(.top, 2)
                        }
                    }
                }

                editorCard(
                    title: localizer.text(.scope),
                    subtitle: localizer.text(.scopeSubtitle),
                    leadingIcon: "scope"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("", selection: $scope) {
                            ForEach(ClipboardSensitiveRuleScope.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 180, alignment: .leading)

                        Divider()

                        VStack(spacing: 10) {
                            settingsToggle(
                                iconName: "textformat",
                                title: localizer.text(.caseSensitive),
                                subtitle: localizer.text(.optionsSubtitle),
                                isOn: $isCaseSensitive
                            )

                            Divider().padding(.leading, 52)

                            settingsToggle(
                                iconName: "checkmark.circle",
                                title: localizer.text(.enabled),
                                subtitle: localizer.text(.ruleEditorSubtitle),
                                isOn: $isEnabled
                            )
                        }
                    }
                }
            }

            HStack {
                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button(localizer.text(.cancel)) {
                        dismiss()
                    }
                    .buttonStyle(ClipboardSensitiveRulePrimaryButtonStyle(kind: .neutral))

                    Button(localizer.text(.save)) {
                        save()
                    }
                    .buttonStyle(ClipboardSensitiveRulePrimaryButtonStyle(kind: .accent))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                }
            }
        }
        .padding(22)
        .frame(width: 620)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.99),
                    Color(red: 0.97, green: 0.98, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            if let rule {
                name = rule.name
                matchType = rule.matchType
                keywordMatchMode = rule.keywordMatchMode
                pattern = rule.pattern
                scope = rule.scope
                isCaseSensitive = rule.isCaseSensitive
                isEnabled = rule.isEnabled
            }
            validatePattern()
        }
        .onChange(of: matchType) { _ in
            validatePattern()
        }
    }

    private var editorHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: rule == nil ? "plus.circle.fill" : "pencil.circle.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(rule == nil ? localizer.text(.addRule) : localizer.text(.editRule))
                    .font(.system(size: 18, weight: .semibold))
                Text(localizer.text(.ruleEditorSubtitle))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var patternSubtitle: String {
        switch matchType {
        case .keyword:
            return localizer.text(.keywordSubtitle)
        case .regex:
            return localizer.text(.regexSubtitle)
        }
    }

    private var patternPlaceholder: String {
        switch matchType {
        case .keyword:
            return localizer.text(.keywordPlaceholder)
        case .regex:
            return localizer.text(.regexPlaceholder)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        regexError == nil
    }

    private func editorCard<Content: View>(
        title: String,
        subtitle: String,
        leadingIcon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.04))

                Image(systemName: leadingIcon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                content()
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.38), lineWidth: 1)
                )
        )
    }

    private func settingsToggle(
        iconName: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.03))

                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private func validatePattern() {
        regexError = nil

        guard matchType == .regex else { return }

        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            _ = try NSRegularExpression(pattern: trimmed)
        } catch {
            regexError = error.localizedDescription
        }
    }

    private func save() {
        var result = rule ?? ClipboardSensitiveRule(
            name: name,
            matchType: matchType,
            pattern: pattern
        )

        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.matchType = matchType
        result.keywordMatchMode = keywordMatchMode
        result.pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        result.scope = scope
        result.isCaseSensitive = isCaseSensitive
        result.isEnabled = isEnabled
        result.updatedAt = Date()

        onSave(result)
        dismiss()
    }
}
