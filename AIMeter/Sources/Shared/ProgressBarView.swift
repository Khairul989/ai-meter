import SwiftUI

struct ProgressBarView: View {
    let percentage: Int
    let height: CGFloat

    private var color: Color { UsageColor.forUtilization(percentage) }
    private var progress: Double { Double(min(percentage, 100)) / 100.0 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color.opacity(0.2))
                // Fill — gradient masked to fill width
                LinearGradient(
                    colors: [.green, .yellow, .orange, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .mask(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2)
                        .frame(width: geo.size.width * progress)
                }
                .animation(.easeInOut(duration: 0.3), value: percentage)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage")
        .accessibilityValue("\(percentage) percent")
    }
}
