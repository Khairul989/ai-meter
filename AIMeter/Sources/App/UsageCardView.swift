import SwiftUI

struct UsageCardView: View {
    let icon: String
    let title: String
    let subtitle: String
    let percentage: Int
    let resetText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(UsageColor.forUtilization(percentage))
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(percentage)%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(UsageColor.forUtilization(percentage))
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
        .padding(.vertical, 8)
    }
}
