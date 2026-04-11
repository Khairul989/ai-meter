import SwiftUI
import AppKit

struct MinimaxTabView: View {
    @ObservedObject var minimaxService: MinimaxService
    @ObservedObject var historyService: MinimaxHistoryService
    @EnvironmentObject private var apiKeyAuthManagers: APIKeyAuthManagers
    @State private var expandedModels: Set<String> = []
    var onKeySaved: (() -> Void)? = nil

    private var authManager: APIKeyAuthManager { apiKeyAuthManagers.minimax }
    private var maxScrollHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) * 0.6
    }

    var body: some View {
        if minimaxService.error == .noKey {
            APIKeyInputView(
                providerName: "MiniMax",
                placeholder: "MINIMAX_API_KEY…",
                accentColor: ProviderTheme.minimax.accentColor
            ) { key in
                authManager.addAccount(label: "Default", apiKey: key)
                onKeySaved?()
            }
        } else {
            VStack(spacing: 8) {
                if authManager.accounts.count > 1 {
                    accountSwitcher
                }
                if case .fetchFailed = minimaxService.error {
                    ErrorBannerView(message: "Failed to fetch MiniMax data") {
                        Task { await minimaxService.fetch() }
                    }
                }
                if case .rateLimited = minimaxService.error {
                    ErrorBannerView(message: "Rate limited — retrying", retryDate: minimaxService.retryDate)
                }

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
                        ForEach(minimaxService.minimaxData.models) { model in
                            DisclosureGroup(isExpanded: isExpanded(model.modelName)) {
                                VStack(spacing: 8) {
                                    UsageCardView(
                                        icon: "waveform.path",
                                        title: "Interval Quota",
                                        subtitle: "\(model.intervalUsed)/\(model.intervalTotal) used",
                                        percentage: model.intervalPercent,
                                        resetText: ResetTimeFormatter.format(model.resetsAt, style: .countdown),
                                        accentColor: ProviderTheme.minimax.accentColor
                                    )

                                    UsageCardView(
                                        icon: "calendar.badge.clock",
                                        title: "Weekly Quota",
                                        subtitle: "\(model.weeklyUsed)/\(model.weeklyTotal) used",
                                        percentage: model.weeklyPercent,
                                        resetText: ResetTimeFormatter.format(model.weeklyResetsAt, style: .dayTime),
                                        accentColor: ProviderTheme.minimax.accentColor
                                    )
                                }
                                .padding(.top, 4)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(model.modelName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.1))
                                            .frame(width: 60, height: 4)
                                        Capsule()
                                            .fill(ProviderTheme.minimax.accentColor)
                                            .frame(width: 60 * CGFloat(maxPercent(for: model)) / 100, height: 4)
                                    }
                                    Text("\(maxPercent(for: model))%")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .frame(width: 30, alignment: .trailing)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                            }
                        }

                        UsageHistoryChartView(
                            title: "Interval % History",
                            dataPoints: historyService.history.dataPoints.map {
                                (date: $0.timestamp, value: Double($0.intervalPercent), label: shortDateLabel($0.timestamp))
                            },
                            valueFormatter: { "\(Int($0))%" },
                            accentColor: ProviderTheme.minimax.accentColor
                        )
                    }
                }
                .frame(maxHeight: maxScrollHeight)
            }
            .onAppear {
                updateExpandedModels()
            }
            .onChange(of: minimaxService.minimaxData.models) { _ in
                updateExpandedModels()
            }
        }
    }

    private func isExpanded(_ modelName: String) -> Binding<Bool> {
        Binding(
            get: { expandedModels.contains(modelName) },
            set: {
                if $0 {
                    expandedModels.insert(modelName)
                } else {
                    expandedModels.remove(modelName)
                }
            }
        )
    }

    private func maxPercent(for model: MinimaxModelQuota) -> Int {
        max(model.intervalPercent, model.weeklyPercent)
    }

    private func updateExpandedModels() {
        let active = Set(
            minimaxService.minimaxData.models
                .filter { $0.intervalPercent > 0 || $0.weeklyPercent > 0 }
                .map(\.modelName)
        )
        let newModels = Set(minimaxService.minimaxData.models.map(\.modelName))
        let toAdd: Set<String>
        if active.isEmpty {
            toAdd = minimaxService.minimaxData.models.first.map { [$0.modelName] }.map(Set.init) ?? []
        } else {
            toAdd = active
        }
        expandedModels = expandedModels.intersection(newModels).union(toAdd)
    }

    private func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var accountSwitcher: some View {
        HStack {
            Menu {
                ForEach(authManager.accounts) { account in
                    Button {
                        authManager.setActiveAccount(account.id)
                    } label: {
                        HStack {
                            Text(account.label)
                            if account.id == authManager.activeAccountId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(authManager.activeAccount?.label ?? "")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
    }
}
