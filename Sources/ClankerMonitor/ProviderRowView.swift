import SwiftUI

struct ProviderRowView: View {
    @EnvironmentObject var appState: AppState

    let provider: Provider

    var body: some View {
        let result = appState.results[provider]

        VStack(alignment: .leading, spacing: 10) {
            header(result: result)

            if let message = result?.errorMessage, !message.isEmpty {
                errorCallout(message)
            } else if let pct = result?.usedPercent {
                usageSection(title: "Current", percent: pct, resetDescription: result?.resetDescription)

                if let weekly = result?.weeklyUsedPercent {
                    Divider().opacity(0.35)
                    usageSection(title: "Weekly", percent: weekly, resetDescription: result?.weeklyResetDescription)
                }
            } else {
                Text("No usage data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(cardBackground)
    }

    private func progressColor(for pct: Double) -> Color {
        if pct >= 90 { return .red }
        if pct >= 75 { return .orange }
        return .teal
    }

    private func header(result: ProviderResult?) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: provider.iconName)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(.white.opacity(0.16))
                )

            Text(provider.displayName)
                .font(.body.weight(.semibold))

            Spacer(minLength: 6)

            if let plan = result?.planLabel, !plan.isEmpty {
                Text(plan)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.1))
                    )
            }
        }
    }

    private func usageSection(title: String, percent: Double, resetDescription: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(percent.rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(progressColor(for: percent))
            }

            usageBar(percent: percent)

            if let resetDescription, !resetDescription.isEmpty {
                Text(resetDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func usageBar(percent: Double) -> some View {
        let clampedPercent = min(max(percent, 0), 100)

        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.12))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [progressColor(for: clampedPercent).opacity(0.6), progressColor(for: clampedPercent)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * (clampedPercent / 100))
            }
        }
        .frame(height: 8)
    }

    private func errorCallout(_ message: String) -> some View {
        Label(String(message.prefix(100)), systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
    }
}
