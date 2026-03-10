import SwiftUI

struct ProviderRowView: View {
    @EnvironmentObject var appState: AppState

    let provider: Provider

    var body: some View {
        let result = appState.results[provider]

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label {
                    Text(provider.displayName)
                        .font(.body.weight(.medium))
                } icon: {
                    Image(systemName: provider.iconName)
                        .foregroundColor(.accentColor)
                }

                Spacer(minLength: 8)

                if let plan = result?.planLabel, !plan.isEmpty {
                    Text(plan)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let message = result?.errorMessage, !message.isEmpty {
                Label(String(message.prefix(80)), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .lineLimit(2)
            } else if let pct = result?.usedPercent {
                HStack(spacing: 8) {
                    ProgressView(value: pct, total: 100)
                        .tint(progressColor(for: pct))
                        .frame(maxWidth: .infinity)

                    Text("\(Int(pct))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                if let reset = result?.resetDescription {
                    Text(reset)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.35))
        )
    }

    private func progressColor(for pct: Double) -> Color {
        if pct >= 90 { return .red }
        if pct >= 75 { return .orange }
        return .blue
    }
}
