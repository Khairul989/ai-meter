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
                // Fill
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color)
                    .frame(width: geo.size.width * progress)
                    .animation(.easeInOut(duration: 0.3), value: percentage)
            }
        }
        .frame(height: height)
    }
}
