import SwiftUI

struct ProxIcon: View {
    var size: CGFloat = 48

    var body: some View {
        HStack(spacing: size * 0.3) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundColor(.primary)

            Text("Prox")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundColor(.primary)
        }
    }
}
