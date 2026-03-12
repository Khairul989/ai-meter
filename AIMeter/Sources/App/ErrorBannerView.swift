import SwiftUI

struct ErrorBannerView: View {
    let message: String
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.orange)
            Spacer()
            if let onRetry {
                Button("Retry") { onRetry() }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(.orange)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityHint(onRetry != nil ? "Tap Retry to try again" : "")
    }
}
