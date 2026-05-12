import SwiftUI

struct DistanceOverlay: View {
    let distance: Float?
    let confidence: Int?
    var onCapture: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            crosshair

            Button(action: { onCapture?() }) {
                Text(distanceString)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: distance)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                if let c = confidence {
                    Circle()
                        .fill(confidenceColor(c))
                        .frame(width: 8, height: 8)
                }
                Text(distance != nil ? unitLabel : "")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
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
        if d < 0.3 {
            switch unit {
            case .metric: return "< 0.3"
            case .imperial: return "< 1'"
            }
        }
        switch unit {
        case .metric:
            return String(format: "%.2f", d)
        case .imperial:
            let totalInches = d * 39.3701
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
            return "\(feet)' \(inches)\""
        }
    }

    private var unitLabel: String {
        switch unit {
        case .metric: return "meters"
        case .imperial: return "feet / inches"
        }
    }

    private func confidenceColor(_ c: Int) -> Color {
        switch c {
        case 2: return .green
        case 1: return .yellow
        default: return .red
        }
    }

    @AppStorage("unit") private var unit: DistanceUnit = .metric
}
