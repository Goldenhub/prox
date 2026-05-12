import SwiftUI

struct DistanceOverlay: View {
    let distance: Float?

    var body: some View {
        VStack(spacing: 16) {
            crosshair

            Text(distanceString)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                .contentTransition(.numericText())
                .animation(.snappy, value: distance)

            Text(distance != nil ? "meters" : "")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
        }
    }

    private var crosshair: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.6), lineWidth: 2)
                .frame(width: 40, height: 40)

            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 4, height: 4)
        }
        .shadow(color: .black.opacity(0.3), radius: 2)
    }

    private var distanceString: String {
        guard let d = distance else { return "---" }
        if d < 0.3 { return "< 0.3" }
        return String(format: "%.2f", d)
    }
}
