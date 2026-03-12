import SwiftUI

struct CountingText: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View {
        Text("\(Int(value))%")
            .font(.system(size: 20, weight: .bold, design: .rounded))
    }
}

struct UsageCardView: View {
    let icon: String
    let title: String
    let subtitle: String
    let percentage: Int
    let resetText: String?
    var accentColor: Color? = nil
    var isPrimary: Bool = false
    var isCompact: Bool = false
    @State private var isHovered = false

    var body: some View {
        if isCompact {
            compactLayout
        } else {
            fullLayout
        }
    }

    private var fullLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(UsageColor.forUtilization(percentage))
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                CountingText(value: Double(percentage))
                    .foregroundColor(UsageColor.forUtilization(percentage))
                    .animation(.easeInOut(duration: 0.4), value: percentage)
            }
            HStack {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if let resetText {
                    Text("Reset \(resetText)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            ProgressBarView(percentage: percentage, height: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(alignment: .leading) {
            if let accentColor {
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: isPrimary ? 3 : 2)
                    .foregroundColor(accentColor)
            }
        }
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .brightness(isHovered ? 0.05 : 0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) usage, \(percentage) percent. \(subtitle)")
        .accessibilityValue(resetText.map { "Reset \($0)" } ?? "")
    }

    private var compactLayout: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(UsageColor.forUtilization(percentage))
                .font(.system(size: 12))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
            ProgressBarView(percentage: percentage, height: 4)
            Text("\(percentage)%")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(UsageColor.forUtilization(percentage))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(alignment: .leading) {
            if let accentColor {
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: isPrimary ? 3 : 2)
                    .foregroundColor(accentColor)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) usage, \(percentage) percent. \(subtitle)")
        .accessibilityValue(resetText.map { "Reset \($0)" } ?? "")
    }
}
