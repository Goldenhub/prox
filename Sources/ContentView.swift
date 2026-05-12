import SwiftUI
import ARKit

enum AppMode: String, CaseIterable {
    case measure = "Measure"
    case scan = "Scan"
}

struct CapturedDistance: Identifiable {
    let id = UUID()
    let distance: Float
    var label: String
    let date: Date
    var positions: [SIMD3<Float>]?
}

struct SegmentInfo: Identifiable {
    let id = UUID()
    let index: Int
    let distance: Float
    let start: SIMD3<Float>
    let end: SIMD3<Float>
}

struct ContentView: View {
    @State private var distance: Float?
    @State private var depthConfidence: Int?
    @State private var mode: AppMode = .measure
    @State private var meshAnchors: [ARMeshAnchor] = []
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var placedMarkers: [PlacedMarker] = []
    @State private var capturedDistances: [CapturedDistance] = []
    @State private var scanRestartTrigger = UUID()
    @State private var showingLabelPrompt = false
    @State private var labelText = ""
    @State private var pendingFreezeDistance: Float?
    @State private var editingLabelID: UUID?
    @State private var showSegmentSheet = false
    @State private var isLiDARSupported: Bool?
    @State private var viewingHistorySegments: CapturedDistance?
    @State private var activeMeasurementID: UUID?
    @State private var selectedBadge: CapturedDistance?
    @State private var showBadgeActions = false
    @State private var showMarkersActions = false
    @State private var freezeAnimating = false
    @State private var confirmClearCaptured = false
    @AppStorage("hasSeenHelp") private var hasSeenHelp = false

    var body: some View {
        Group {
            if isLiDARSupported == false {
                unsupportedView
            } else {
                mainView
            }
        }
        .task {
            isLiDARSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
        }
        .onAppear {
            if !hasSeenHelp {
                hasSeenHelp = true
                showHelp = true
            }
        }
    }

    private var unsupportedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("LiDAR Required")
                .font(.title.weight(.bold))
            Text("Prox needs a device with a LiDAR scanner (iPhone 12–16 Pro / iPad Pro).")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
        }
    }

    private var mainView: some View {
        ZStack {
            switch mode {
            case .measure:
                ARViewContainer(distance: $distance, confidence: $depthConfidence, placedMarkers: $placedMarkers, onCaptureDistance: onDistanceTap)
                    .edgesIgnoringSafeArea(.all)
                    .transition(.opacity)
            case .scan:
                RoomScanner(meshAnchors: $meshAnchors, restartTrigger: $scanRestartTrigger)
                    .edgesIgnoringSafeArea(.all)
                    .transition(.opacity)
            }

            VStack {
                HStack {
                    HStack(spacing: 8) {
                        helpButton
                        settingsButton
                    }
                    Spacer()
                }
                .padding(.top, 56)
                .padding(.leading, 16)

                Spacer()

                if mode == .measure {
                    DistanceOverlay(distance: distance, confidence: depthConfidence, onCapture: onDistanceTap)
                        .padding(.bottom, distance != nil ? 60 : 120)

                    if distance != nil {
                        freezeButton
                            .padding(.bottom, 6)
                    }

                    if !capturedDistances.isEmpty {
                        capturedList
                            .padding(.bottom, 6)
                    }

                    Group {
                        if !placedMarkers.isEmpty {
                            markersBadge
                        }
                    }
                    .padding(.bottom, 8)
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        .sheet(isPresented: $showSegmentSheet) {
            segmentListView
        }
        .alert("Export Failed", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: mode) { _, _ in HapticManager.selection() }
        .onChange(of: showSegmentSheet) { _, showing in
            if !showing, activeMeasurementID != nil {
                placedMarkers = []
                activeMeasurementID = nil
                viewingHistorySegments = nil
            }
        }
        .confirmationDialog("Points", isPresented: $showMarkersActions) {
            Button("Save") { saveAllSegments() }
            Button(role: .destructive) {
                placedMarkers = []
                showSegmentSheet = false
                activeMeasurementID = nil
            } label: { Text("Delete") }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Measurement", isPresented: $showBadgeActions, presenting: selectedBadge) { c in
            Button("Rename") {
                editingLabelID = c.id
                labelText = c.label
                pendingFreezeDistance = nil
                showingLabelPrompt = true
            }
            Button(role: .destructive) {
                if let idx = capturedDistances.firstIndex(where: { $0.id == c.id }) {
                    capturedDistances.remove(at: idx)
                }
            } label: {
                Text("Delete")
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Name this measurement", isPresented: $showingLabelPrompt) {
            TextField("e.g. Door width", text: $labelText)
            Button("Save") { commitLabel() }
            Button("Skip", role: .cancel) {
                if let d = pendingFreezeDistance {
                    capturedDistances.append(CapturedDistance(distance: d, label: "", date: Date()))
                    pendingFreezeDistance = nil
                }
                editingLabelID = nil
            }
        }
    }

    private var helpButton: some View {
        Button(action: { showHelp = true }) {
            Image(systemName: "questionmark.circle")
                .font(.title3)
                .foregroundColor(.white)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private var settingsButton: some View {
        Button(action: { showSettings = true }) {
            Image(systemName: "gear")
                .font(.title3)
                .foregroundColor(.white)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private var freezeButton: some View {
        Button(action: captureDistance) {
            Image(systemName: "target")
                .font(.title2)
                .foregroundColor(.white)
                .padding(14)
                .background(.blue, in: Circle())
                .shadow(radius: 4)
        }
        .scaleEffect(freezeAnimating ? 1.3 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.4), value: freezeAnimating)
    }

    private var capturedList: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(capturedDistances) { c in
                        capturedDistanceBadge(c)
                    }
                }
                .padding(.horizontal, 16)
            }

            Button(action: { confirmClearCaptured = true }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .confirmationDialog("Clear all measurements?", isPresented: $confirmClearCaptured) {
                Button("Clear All", role: .destructive) { capturedDistances = [] }
                Button("Cancel", role: .cancel) {}
            }
            .padding(.trailing, 12)
        }
    }

    private func capturedDistanceBadge(_ c: CapturedDistance) -> some View {
        HStack(spacing: 4) {
            Image(systemName: c.positions != nil ? "point.topleft.down.curvedto.point.bottomright.up" : "ruler")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
            VStack(spacing: 1) {
                if !c.label.isEmpty {
                    Text(c.label)
                        .font(.caption2.weight(.medium))
                }
                Text(freezeDistanceString(c.distance))
                    .font(.caption.monospacedDigit().weight(c.label.isEmpty ? .medium : .regular))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .onTapGesture {
            if c.id == activeMeasurementID {
                placedMarkers = []
                showSegmentSheet = false
                activeMeasurementID = nil
                return
            }
            if let positions = c.positions, positions.count > 1 {
                placedMarkers = positions.enumerated().map { i, pos in
                    let prevDist: Float? = i > 0 ? length(pos - positions[i - 1]) : nil
                    return PlacedMarker(position: pos, distance: prevDist)
                }
                viewingHistorySegments = c
                activeMeasurementID = c.id
                showSegmentSheet = true
            } else {
                editingLabelID = c.id
                labelText = c.label
                pendingFreezeDistance = nil
                showingLabelPrompt = true
            }
        }
        .onLongPressGesture {
            selectedBadge = c
            showBadgeActions = true
            HapticManager.impact(.medium)
        }
    }

    private func freezeDistanceString(_ d: Float) -> String {
        let unit = UserDefaults.standard.string(forKey: "unit") ?? "metric"
        if unit == "imperial" {
            let totalInches = d * 39.3701
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
            return "\(feet)' \(inches)\""
        }
        return String(format: "%.2fm", d)
    }

    private func onDistanceTap() {
        if !placedMarkers.isEmpty {
            viewingHistorySegments = nil
            showSegmentSheet = true
        } else {
            captureDistance()
        }
    }

    private func captureDistance() {
        guard let d = distance else { return }
        HapticManager.impact(.light)
        freezeAnimating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            freezeAnimating = false
        }
        pendingFreezeDistance = d
        labelText = ""
        editingLabelID = nil
        showingLabelPrompt = true
    }

    private func commitLabel() {
        if let editID = editingLabelID {
            if let idx = capturedDistances.firstIndex(where: { $0.id == editID }) {
                capturedDistances[idx].label = labelText
            }
            editingLabelID = nil
        } else if let d = pendingFreezeDistance {
            capturedDistances.append(CapturedDistance(distance: d, label: labelText, date: Date()))
            pendingFreezeDistance = nil
        }
    }

    private var markersBadge: some View {
        HStack(spacing: 12) {
            Text("\(placedMarkers.count) pt")
                .font(.caption.monospacedDigit())
                .foregroundColor(.white)

            if placedMarkers.count > 1 {
                let total = placedMarkers.compactMap(\.distance).reduce(0, +)
                Text(markerDistanceString(total))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .onTapGesture { showSegmentSheet = true }
        .onLongPressGesture {
            showMarkersActions = true
            HapticManager.impact(.medium)
        }
    }

    private var segmentListView: some View {
        let segments = currentSegments()
        return NavigationStack {
            List {
                ForEach(segments) { seg in
                    HStack {
                        Text("P\(seg.index)→P\(seg.index + 1)")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(freezeDistanceString(seg.distance))
                            .font(.title3.monospacedDigit().weight(.bold))
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("Inter-Point Lengths")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSegmentSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func currentSegments() -> [SegmentInfo] {
        if let stored = viewingHistorySegments, let positions = stored.positions, positions.count > 1 {
            return positions.enumerated().compactMap { i, pos in
                guard i > 0 else { return nil }
                let d = length(pos - positions[i - 1])
                return SegmentInfo(index: i, distance: d, start: positions[i - 1], end: pos)
            }
        }
        guard placedMarkers.count > 1 else { return [] }
        return placedMarkers.enumerated().compactMap { i, m in
            guard i > 0, let d = m.distance else { return nil }
            return SegmentInfo(index: i, distance: d, start: placedMarkers[i - 1].position, end: m.position)
        }
    }

    private func saveAllSegments() {
        let total = placedMarkers.compactMap(\.distance).reduce(0, +)
        let positions = placedMarkers.map(\.position)
        capturedDistances.append(CapturedDistance(
            distance: total,
            label: "Points (\(placedMarkers.count))",
            date: Date(),
            positions: positions
        ))
        placedMarkers = []
        showSegmentSheet = false
        HapticManager.success()
    }

    private func markerDistanceString(_ d: Float) -> String {
        let unit = UserDefaults.standard.string(forKey: "unit") ?? "metric"
        if unit == "imperial" {
            let totalInches = d * 39.3701
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
            return "\(feet)' \(inches)\""
        }
        return String(format: "%.2f m", d)
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
                    HStack(spacing: 12) {
                        saveButton
                        restartScanButton
                    }
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

    private var restartScanButton: some View {
        Button(action: restartScan) {
            Image(systemName: "arrow.counterclockwise")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.red, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func restartScan() {
        meshAnchors = []
        scanRestartTrigger = UUID()
        HapticManager.impact(.medium)
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
        HapticManager.impact(.medium)

        let meshes = meshAnchors.map { MeshExporter.extractMeshData(from: $0) }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = MeshExporter.exportUSDZ(meshes: meshes)
            DispatchQueue.main.async {
                isExporting = false
                if let url = result.url {
                    if !result.errors.isEmpty {
                        print("Export warnings: \(result.errors)")
                    }
                    HapticManager.success()
                    meshAnchors = []
                    exportURL = url
                    showShare = true
                } else {
                    HapticManager.error()
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

struct SettingsView: View {
    @AppStorage("unit") private var unit: DistanceUnit = .metric
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Distance Unit", selection: $unit) {
                    Text("Metric (m)").tag(DistanceUnit.metric)
                    Text("Imperial (ft/in)").tag(DistanceUnit.imperial)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(200)])
    }
}

struct HelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Measure Mode") {
                    LabeledContent("Crosshair", value: "Point the center dot at any surface to see live distance. Green/yellow/red dot shows depth confidence")
                    LabeledContent("Freeze", value: "Tap the target button or the distance number to save a reading")
                    LabeledContent("Markers", value: "Tap anywhere on a surface to place a 3D marker. Consecutive markers are connected with a line")
                    LabeledContent("Marker total", value: "Tap the points badge to view individual segment lengths. Long press for Save (stores total) or Delete")
                    LabeledContent("Saved items", value: "Tap a saved measurement to see its 3D markers and segments. Long press to Rename or Delete")
                    LabeledContent("Live capture", value: "When markers are placed, tapping the distance number opens the inter-point lengths list")
                }

                Section("Scan Mode") {
                    LabeledContent("Scan", value: "Move your phone slowly around the room. ARKit builds a 3D mesh in real time")
                    LabeledContent("Restart", value: "Tap the red restart button to clear the scan and start fresh")
                    LabeledContent("Export", value: "Tap Export USDZ when ready. The file saves and opens a share sheet")
                    LabeledContent("Auto-clear", value: "After successful export, the scan is automatically cleared")
                }

                Section("Settings") {
                    LabeledContent("Units", value: "Switch between meters and feet/inches in Settings")
                }
            }
            .navigationTitle("How to Use Prox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
