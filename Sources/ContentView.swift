import SwiftUI
import ARKit

enum AppMode: String, CaseIterable {
    case measure = "Measure"
    case scan = "Scan"
}

struct ContentView: View {
    @State private var distance: Float?
    @State private var mode: AppMode = .measure
    @State private var meshAnchors: [ARMeshAnchor] = []
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            switch mode {
            case .measure:
                ARViewContainer(distance: $distance)
                    .edgesIgnoringSafeArea(.all)
            case .scan:
                RoomScanner(meshAnchors: $meshAnchors)
                    .edgesIgnoringSafeArea(.all)
            }

            VStack {
                Spacer()
                if mode == .measure {
                    DistanceOverlay(distance: distance)
                        .padding(.bottom, 80)
                }
                controls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .statusBar(hidden: true)
        .sheet(isPresented: $showShare) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Export Failed", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if mode == .scan {
                if meshAnchors.isEmpty {
                    Text("Move camera to scan...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    scanStats
                    saveButton
                }
            }

            Picker("Mode", selection: $mode) {
                ForEach(AppMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
        }
    }

    private var scanStats: some View {
        HStack(spacing: 24) {
            Label("\(meshAnchors.count) meshes", systemImage: "square.3.layers.3d")
            let verts = meshAnchors.reduce(0) { $0 + $1.geometry.vertices.count }
            Label("\(verts) verts", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
        }
        .font(.caption.monospacedDigit())
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var saveButton: some View {
        Button(action: exportMesh) {
            HStack(spacing: 8) {
                if isExporting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.down")
                    Text("Export USDZ")
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.blue, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isExporting)
    }

    private func exportMesh() {
        guard !meshAnchors.isEmpty else { return }

        isExporting = true

        let meshes = meshAnchors.map { MeshExporter.extractMeshData(from: $0) }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = MeshExporter.exportUSDZ(meshes: meshes)
            DispatchQueue.main.async {
                isExporting = false
                if let url = result.url {
                    if !result.errors.isEmpty {
                        print("Export warnings: \(result.errors)")
                    }
                    exportURL = url
                    showShare = true
                } else {
                    errorMessage = result.errors.first ?? "Could not create 3D model."
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
