import Foundation
import SwiftUI

enum Provider: String, CaseIterable, Identifiable {
    case codex
    case copilot
    case claude
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .copilot: return "Copilot"
        case .claude: return "Claude"
        case .opencode: return "OpenCode"
        }
    }

    var iconName: String {
        switch self {
        case .codex: return "sparkles"
        case .copilot: return "chevron.left.forwardslash.chevron.right"
        case .claude: return "brain"
        case .opencode: return "bolt.circle"
        }
    }
}

struct ProviderResult {
    var usedPercent: Double? = nil
    var resetDescription: String? = nil
    var planLabel: String? = nil
    var errorMessage: String? = nil
    var updatedAt: Date? = nil
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var results: [Provider: ProviderResult] = [:]
    @Published var isRefreshing = false

    @AppStorage("copilotPAT") var copilotPAT: String = ""
    @AppStorage("opencodecookie") var opencodeCookie: String = ""
    @AppStorage("providerVisible_codex") var isCodexVisible: Bool = true
    @AppStorage("providerVisible_copilot") var isCopilotVisible: Bool = true
    @AppStorage("providerVisible_claude") var isClaudeVisible: Bool = true
    @AppStorage("providerVisible_opencode") var isOpenCodeVisible: Bool = true

    private init() {}

    func isProviderVisible(_ provider: Provider) -> Bool {
        switch provider {
        case .codex: return isCodexVisible
        case .copilot: return isCopilotVisible
        case .claude: return isClaudeVisible
        case .opencode: return isOpenCodeVisible
        }
    }

    func setProviderVisibility(_ provider: Provider, isVisible: Bool) {
        guard isProviderVisible(provider) != isVisible else { return }
        objectWillChange.send()

        switch provider {
        case .codex: isCodexVisible = isVisible
        case .copilot: isCopilotVisible = isVisible
        case .claude: isClaudeVisible = isVisible
        case .opencode: isOpenCodeVisible = isVisible
        }
    }

    var visibleProviders: [Provider] {
        Provider.allCases.filter { isProviderVisible($0) }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let shouldFetchClaude = isProviderVisible(.claude)

        async let codex = fetchCodex()
        async let copilot = fetchCopilot(token: copilotPAT)
        async let opencode = fetchOpenCode(cookieHeader: opencodeCookie)

        let (codexResult, copilotResult, opencodeResult) = await (codex, copilot, opencode)

        results[.codex] = codexResult
        results[.copilot] = copilotResult
        results[.opencode] = opencodeResult

        if shouldFetchClaude {
            results[.claude] = await fetchClaude()
        }
    }
}
