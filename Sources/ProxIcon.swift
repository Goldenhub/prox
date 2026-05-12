import SwiftUI

struct ProxIcon: View {
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            lines
            points
        }
        .frame(width: size, height: size)
    }

    private var points: some View {
        ZStack {
            Circle().fill(white) .frame(width: dotSize * 1.6, height: dotSize * 1.6) .position(origin)
            Circle().fill(Color(white: 0.3)) .frame(width: dotSize, height: dotSize) .position(origin)
            Circle().fill(.orange) .frame(width: dotSize * 1.6, height: dotSize * 1.6) .position(xPoint)
            Circle().fill(Color(white: 0.3)) .frame(width: dotSize, height: dotSize) .position(xPoint)
            Circle().fill(.blue) .frame(width: dotSize * 1.6, height: dotSize * 1.6) .position(yPoint)
            Circle().fill(Color(white: 0.3)) .frame(width: dotSize, height: dotSize) .position(yPoint)
            Circle().fill(.green) .frame(width: dotSize * 1.6, height: dotSize * 1.6) .position(zPoint)
            Circle().fill(Color(white: 0.3)) .frame(width: dotSize, height: dotSize) .position(zPoint)
        }
    }

    private var lines: some View {
        Canvas { context, _ in
            var originPath = Path()
            originPath.move(to: origin)
            originPath.addLine(to: xPoint)
            context.stroke(originPath, with: .color(.orange), lineWidth: lineWidth)

            var yPath = Path()
            yPath.move(to: origin)
            yPath.addLine(to: yPoint)
            context.stroke(yPath, with: .color(.blue), lineWidth: lineWidth)

            var zPath = Path()
            zPath.move(to: origin)
            zPath.addLine(to: zPoint)
            context.stroke(zPath, with: .color(.green), lineWidth: lineWidth)
        }
    }

    private var dotSize: CGFloat { size * 0.08 }
    private var lineWidth: CGFloat { size * 0.035 }
    private var white: Color { Color(white: 0.85) }

    private var origin: CGPoint { CGPoint(x: size * 0.38, y: size * 0.62) }
    private var xPoint: CGPoint { CGPoint(x: size * 0.88, y: size * 0.62) }
    private var yPoint: CGPoint { CGPoint(x: size * 0.38, y: size * 0.12) }
    private var zPoint: CGPoint { CGPoint(x: size * 0.55, y: size * 0.85) }
}
