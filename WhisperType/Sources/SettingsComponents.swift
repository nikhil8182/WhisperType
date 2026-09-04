import SwiftUI

/// Shared presentation for the settings window. Colors follow system appearance.
enum SettingsPalette {
    static let accent = Color(nsColor: .systemGreen)
}

struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.06)))
    }
}

struct SettingsToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 20)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
                .help(detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PermissionStatusBadge: View {
    let granted: Bool

    var body: some View {
        Label(granted ? "Allowed" : "Needs access", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(granted ? SettingsPalette.accent : Color.orange)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background((granted ? SettingsPalette.accent : Color.orange).opacity(0.10), in: Capsule())
    }
}

struct SettingsEmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(SettingsPalette.accent)
                .frame(width: 64, height: 64)
                .background(SettingsPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
        }
        .padding(.vertical, 44)
        .frame(maxWidth: .infinity)
    }
}
