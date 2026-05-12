# Prox

**Proximity, at a glance.** Point and see exact distance to any surface. Then scan your room into a 3D model — all powered by LiDAR.

Two modes:
- **Measure** — real-time crosshair with live distance readout in meters
- **Scan** — build a 3D mesh of your environment and export as USDZ

## Requirements

iPhone 12 Pro+ or iPad Pro (2020+). Simulator won't work — LiDAR is real hardware only.

Xcode 15.4+, iOS 17.0+, free Apple Developer account.

## Quick Start

1. Open `Prox.xcodeproj` in Xcode
2. Connect your iPhone via USB
3. Select your iPhone as the run destination
4. Set your team in Signing & Capabilities if needed
5. Press **Cmd+R**

---

## Architecture

```
Prox.xcodeproj
└── Sources/
    ├── ProxApp.swift           — @main entry point
    ├── ContentView.swift       — Root view: Measure/Scan mode switcher
    ├── ARViewContainer.swift   — LiDAR depth measurement (ARKit + RealityKit)
    ├── DistanceOverlay.swift   — Crosshair + distance display
    ├── RoomScanner.swift       — Scene reconstruction mesh viewer
    └── MeshExporter.swift      — USDZ export via ModelIO
```

### Measure Mode

Uses `ARWorldTrackingConfiguration` with `.smoothedSceneDepth` frame semantics. Each frame samples the center pixel of the LiDAR depth map (256×192 Float32 buffer), mapped through ARKit's `displayTransform` to account for orientation and aspect ratio.

### Scan Mode

Enables `sceneReconstruction(.meshWithClassification)` on the configuration. ARKit's `ARMeshAnchor` callbacks feed live mesh data to the UI. On export, geometry data is copied from Metal buffers to plain Swift arrays on the main thread, then converted to `MDLMesh` objects and assembled into a `MDLAsset` for USDZ export.

---

## Technical Reference

| Component | Technology |
|---|---|
| Depth API | `ARFrame.smoothedSceneDepth` / `sceneDepth` |
| Depth format | `kCVPixelFormatType_DepthFloat32`, ~256×192 |
| Scene reconstruction | `ARMeshAnchor` (triangle faces) |
| 3D export | `ModelIO` → `MDLAsset.export()` → `.usdz` |
| UI framework | SwiftUI |
| AR framework | RealityKit ARView + ARKit |
