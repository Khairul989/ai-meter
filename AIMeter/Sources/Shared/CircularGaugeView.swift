import SwiftUI

struct CircularGaugeView: View {
    let percentage: Int
    let lineWidth: CGFloat
    let size: CGFloat

    private var color: Color { UsageColor.forUtilization(percentage) }
    private var progress: Double { Double(percentage) / 100.0 }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: percentage)
            // Percentage text
            Text("\(percentage)%")
                .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}
