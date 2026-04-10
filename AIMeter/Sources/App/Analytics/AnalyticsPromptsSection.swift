import SwiftUI

struct AnalyticsPromptsSection: View {
    let result: AnalyticsResult

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prompts")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            LazyVGrid(columns: columns, spacing: 8) {
                promptCard(label: "Median", value: ModelPricing.formatTokens(Int(result.tokensPerPrompt.medianTokensPerPrompt.rounded())), color: .white)
                promptCard(label: "Average", value: ModelPricing.formatTokens(Int(result.tokensPerPrompt.avgTokensPerPrompt.rounded())), color: .white.opacity(0.85))
                promptCard(label: "Min", value: ModelPricing.formatTokens(result.tokensPerPrompt.minTokensPerPrompt), color: .green)
                promptCard(label: "Max", value: ModelPricing.formatTokens(result.tokensPerPrompt.maxTokensPerPrompt), color: .red)
            }

            Text("Each prompt costs ~\(ModelPricing.formatTokens(Int(result.tokensPerPrompt.avgTokensPerPrompt.rounded()))) tokens on average")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            headerRow

            ForEach(result.tokensPerPrompt.top10ExpensiveSessions) { session in
                HStack(spacing: 10) {
                    Text(session.projectName)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(width: 200, alignment: .leading)

                    Text(ModelPricing.formatTokens(tokensPerPrompt(for: session)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red)
                        .frame(width: 82, alignment: .trailing)

                    Text(ModelPricing.formatTokens(session.totalTokens))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 82, alignment: .trailing)

                    Text("\(session.promptCount)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("Project")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 200, alignment: .leading)
            Text("Tok/Prompt")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 82, alignment: .trailing)
            Text("Total")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 82, alignment: .trailing)
            Text("Prompts")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 54, alignment: .trailing)
        }
    }

    private func promptCard(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func tokensPerPrompt(for session: SessionSummary) -> Int {
        guard session.promptCount > 0 else { return 0 }
        return session.totalTokens / session.promptCount
    }
}
