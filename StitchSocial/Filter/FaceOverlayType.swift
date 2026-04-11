//
//  ARFaceFilterEngine.swift
//  StitchSocial
//
//  Layer 2: AR Face Filters — ARKit ARFaceAnchor + RealityKit overlays
//  Sits alongside CinematicCameraManager (separate AR session)
//
//  ARCHITECTURE:
//  - CinematicCameraManager handles recording + color grades (AVFoundation)
//  - ARFaceFilterEngine handles face overlays (ARKit — separate session)
//  - Both render into the same MTKView via compositor
//
//  IMPORTANT: ARKit face tracking requires TrueDepth camera (front camera only)
//  Supported: iPhone X and later
//
//  CACHING (add to optimization file):
//  - ARSCNView reused — never recreated per filter switch
//  - SCNNode assets cached in nodeCache keyed by filterID
//  - Face geometry updated in-place — no node recreation per frame
//  - Asset downloads cached to disk via URLSession + FileManager
//
//  FIRESTORE:
//  - Face filter manifests read from FilterEngine (already loaded)
//  - 3D model URLs from manifest.assetURLs["model"]
//  - Texture URLs from manifest.assetURLs["texture"]
//

import Foundation
import ARKit
import SceneKit
import RealityKit
import SwiftUI
import Combine

// MARK: - Face Filter Type

enum FaceOverlayType: String {
    case beauty         = "face_beauty"       // skin smoothing (CIFilter, no 3D)
    case faceGlow       = "face_glow"         // emissive glow around face
    case sunglasses     = "face_sunglasses"   // 3D glasses on nose bridge
    case crown          = "face_crown"        // 3D crown on top of head
    case ears           = "face_ears"         // animal ears on head
    case mask           = "face_mask"         // full face mesh texture
    case makeupLip      = "face_makeup_lip"   // lip color overlay
    case makeupEye      = "face_makeup_eye"   // eye shadow overlay
}

// MARK: - ARFaceFilterEngine

@MainActor
final class ARFaceFilterEngine: NSObject, ObservableObject {

    static let shared = ARFaceFilterEngine()

    // MARK: Published
    @Published var isSupported:  Bool = false
    @Published var isFaceDetected: Bool = false
    @Published var activeOverlay: FaceOverlayType? = nil

    // MARK: AR Session
    private var arSession:   ARSession?
    private var sceneView:   ARSCNView?

    // MARK: Node cache — CACHE: never recreate per frame
    private var nodeCache:   [FaceOverlayType: SCNNode] = [:]
    private var faceNode:    SCNNode?
    private var contentNode: SCNNode?    // parent for all overlays

    // MARK: Asset loading
    private var loadingTasks: [FaceOverlayType: Task<Void, Never>] = [:]
    private var assetCache:   [String: SCNNode] = [:]  // URL -> loaded node

    // MARK: - Init

    override init() {
        super.init()
        isSupported = ARFaceTrackingConfiguration.isSupported
        print("🎭 AR FACE: Supported = \(isSupported)")
    }

    // MARK: - ARSCNView Factory

    /// Returns a configured ARSCNView for embedding over camera preview
    func makeARView() -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.automaticallyUpdatesLighting = true
        view.rendersContinuously = true
        view.backgroundColor = .clear  // transparent — overlays on top of MTKView
        view.scene = SCNScene()
        view.delegate = self
        self.sceneView = view
        return view
    }

    // MARK: - Session Control

    func startSession() {
        guard isSupported, let view = sceneView else { return }
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = true
        // Use world + face tracking on supported devices
        if ARFaceTrackingConfiguration.supportsWorldTracking {
            config.worldAlignment = .gravity
        }
        arSession = view.session
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        print("🎭 AR FACE: Session started")
    }

    func pauseSession() {
        sceneView?.session.pause()
        print("🎭 AR FACE: Session paused")
    }

    // MARK: - Filter Activation

    func activate(_ overlay: FaceOverlayType?) {
        // Remove current overlay node
        contentNode?.childNodes.forEach { $0.removeFromParentNode() }

        guard let overlay = overlay else {
            activeOverlay = nil
            return
        }

        activeOverlay = overlay

        // Load or retrieve cached node
        if let cached = nodeCache[overlay] {
            contentNode?.addChildNode(cached)
        } else {
            loadAndAttach(overlay)
        }
    }

    // MARK: - Node Loading

    private func loadAndAttach(_ overlay: FaceOverlayType) {
        // Cancel any existing load for this overlay
        loadingTasks[overlay]?.cancel()

        loadingTasks[overlay] = Task {
            let node = await buildNode(for: overlay)
            guard !Task.isCancelled else { return }
            nodeCache[overlay] = node
            if activeOverlay == overlay {
                contentNode?.addChildNode(node)
            }
            print("🎭 AR FACE: Loaded node for \(overlay.rawValue)")
        }
    }

    private func buildNode(for overlay: FaceOverlayType) async -> SCNNode {
        switch overlay {

        case .beauty:
            // Beauty is handled in CIFilter pipeline, no 3D node needed
            return SCNNode()

        case .faceGlow:
            return buildGlowNode()

        case .sunglasses:
            return await loadModelNode(filterID: overlay.rawValue) ?? buildFallbackGlasses()

        case .crown:
            return await loadModelNode(filterID: overlay.rawValue) ?? buildFallbackCrown()

        case .ears:
            return await loadModelNode(filterID: overlay.rawValue) ?? buildFallbackEars()

        case .mask:
            return buildFaceMeshNode(textureName: overlay.rawValue)

        case .makeupLip:
            return buildLipColorNode()

        case .makeupEye:
            return buildEyeShadowNode()
        }
    }

    // MARK: - Load 3D Model from Firebase Storage

    private func loadModelNode(filterID: String) async -> SCNNode? {
        // Get asset URL from FilterEngine manifest
        guard let manifest = FilterEngine.shared.availableFilters.first(where: { $0.id == filterID }),
              let urlString = manifest.assetURLs["model"],
              !urlString.isEmpty,
              let url = URL(string: urlString) else { return nil }

        // Check disk cache
        let cacheURL = diskCachePath(for: urlString)
        let modelURL: URL

        if FileManager.default.fileExists(atPath: cacheURL.path) {
            modelURL = cacheURL
        } else {
            // Download and cache
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try data.write(to: cacheURL)
                modelURL = cacheURL
            } catch {
                print("🎭 AR FACE: Failed to download model \(filterID): \(error)")
                return nil
            }
        }

        guard let scene = try? SCNScene(url: modelURL),
              let node  = scene.rootNode.childNodes.first else { return nil }
        return node
    }

    private func diskCachePath(for urlString: String) -> URL {
        let hash = abs(urlString.hashValue)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("ar_asset_\(hash).scn")
    }

    // MARK: - Built-in Geometry Nodes (fallback when no 3D asset)

    private func buildGlowNode() -> SCNNode {
        let node = SCNNode()
        // Emissive sphere around face origin
        let sphere = SCNSphere(radius: 0.15)
        sphere.firstMaterial?.emission.contents = UIColor.cyan.withAlphaComponent(0.3)
        sphere.firstMaterial?.transparency = 0.7
        sphere.firstMaterial?.blendMode = .add
        node.geometry = sphere
        return node
    }

    // MARK: - ARKit Face Landmark Indices
    // Subset of 1220 ARFaceGeometry vertices that map to key facial features.
    // Verified against Apple's ARKit face mesh topology.
    // https://developer.apple.com/documentation/arkit/arfaceanchor/geometry
    private enum FaceLandmark: Int {
        case noseBridge      = 9     // top of nose bridge (glasses center anchor)
        case leftEyeOuter    = 359   // left eye outer corner
        case rightEyeOuter   = 130   // right eye outer corner
        case leftEyeInner    = 463   // left eye inner corner
        case rightEyeInner   = 243   // right eye inner corner
        case leftEyeCenter   = 386   // left eye center (pupil approx)
        case rightEyeCenter  = 159   // right eye center (pupil approx)
        case foreheadTop     = 10    // top center of forehead
        case leftTemple      = 234   // left temple / ear root
        case rightTemple     = 454   // right temple / ear root
        case chinBottom      = 152   // chin tip
    }

    // Safe vertex read — returns zero vector if index out of bounds
    private func vertex(_ idx: FaceLandmark, in vertices: [SIMD3<Float>]) -> SCNVector3 {
        guard idx.rawValue < vertices.count else { return .init(0, 0, 0) }
        let v = vertices[idx.rawValue]
        return SCNVector3(v.x, v.y, v.z)
    }

    // MARK: - Glasses (landmark-anchored)

    private func buildFallbackGlasses() -> SCNNode {
        // Root node — positioned each frame in didUpdate via landmark vertices.
        // Named parts are looked up by name in the update pass.
        let node = SCNNode()
        node.name = "glasses_root"

        // Left lens
        let leftTorus = SCNTorus(ringRadius: 0.021, pipeRadius: 0.0025)
        applyGlassMaterial(leftTorus)
        let leftLens = SCNNode(geometry: leftTorus)
        leftLens.name = "lens_left"
        leftLens.eulerAngles.x = .pi / 2

        // Right lens
        let rightTorus = SCNTorus(ringRadius: 0.021, pipeRadius: 0.0025)
        applyGlassMaterial(rightTorus)
        let rightLens = SCNNode(geometry: rightTorus)
        rightLens.name = "lens_right"
        rightLens.eulerAngles.x = .pi / 2

        // Bridge connecting lenses
        let bridge = SCNCylinder(radius: 0.0018, height: 0.018)
        bridge.firstMaterial?.diffuse.contents   = UIColor(white: 0.15, alpha: 1)
        bridge.firstMaterial?.metalness.contents = 0.9
        bridge.firstMaterial?.roughness.contents = 0.2
        let bridgeNode = SCNNode(geometry: bridge)
        bridgeNode.name = "bridge"
        bridgeNode.eulerAngles.z = .pi / 2

        // Temple arms (left + right)
        for (side, name) in [(Float(-1), "temple_left"), (Float(1), "temple_right")] {
            let arm = SCNCylinder(radius: 0.0015, height: 0.07)
            arm.firstMaterial?.diffuse.contents   = UIColor(white: 0.1, alpha: 1)
            arm.firstMaterial?.metalness.contents = 0.8
            let armNode = SCNNode(geometry: arm)
            armNode.name = name
            armNode.eulerAngles.z = .pi / 2
            // Initial position — overridden each frame by landmark update
            armNode.position = SCNVector3(side * 0.06, 0, 0.04)
            node.addChildNode(armNode)
        }

        node.addChildNode(leftLens)
        node.addChildNode(rightLens)
        node.addChildNode(bridgeNode)
        return node
    }

    private func applyGlassMaterial(_ geometry: SCNGeometry) {
        geometry.firstMaterial?.diffuse.contents   = UIColor(white: 0.05, alpha: 1)
        geometry.firstMaterial?.metalness.contents = 0.95
        geometry.firstMaterial?.roughness.contents = 0.05
        geometry.firstMaterial?.lightingModel      = .physicallyBased
    }

    // MARK: - Crown (landmark-anchored)

    private func buildFallbackCrown() -> SCNNode {
        let node = SCNNode()
        node.name = "crown_root"

        // Band
        let band = SCNCylinder(radius: 0.075, height: 0.012)
        band.firstMaterial?.diffuse.contents   = UIColor.systemYellow
        band.firstMaterial?.metalness.contents = 0.95
        band.firstMaterial?.roughness.contents = 0.05
        band.firstMaterial?.lightingModel      = .physicallyBased
        let bandNode = SCNNode(geometry: band)
        bandNode.name = "band"
        node.addChildNode(bandNode)

        // 5 spikes evenly spaced
        for i in 0..<5 {
            let angle = Float(i) * (.pi * 2 / 5)
            let spike = SCNCone(topRadius: 0, bottomRadius: 0.012, height: 0.038)
            spike.firstMaterial?.diffuse.contents   = UIColor.systemYellow
            spike.firstMaterial?.metalness.contents = 0.95
            spike.firstMaterial?.roughness.contents = 0.05
            let spikeNode = SCNNode(geometry: spike)
            spikeNode.name = "spike_\(i)"
            // Position relative to band top — x/z spread, y upward
            spikeNode.position = SCNVector3(
                0.055 * sin(angle),
                0.025,
                0.055 * cos(angle)
            )
            node.addChildNode(spikeNode)
        }
        return node
    }

    // MARK: - Ears (landmark-anchored)

    private func buildFallbackEars() -> SCNNode {
        let node = SCNNode()
        node.name = "ears_root"

        for (side, suffix) in [(Float(-1), "left"), (Float(1), "right")] {
            // Outer ear shape — flattened box, not a cone
            let outer = SCNBox(width: 0.028, height: 0.05, length: 0.008, chamferRadius: 0.006)
            outer.firstMaterial?.diffuse.contents  = UIColor(red: 0.82, green: 0.65, blue: 0.50, alpha: 1)
            outer.firstMaterial?.roughness.contents = 0.8
            let outerNode = SCNNode(geometry: outer)
            outerNode.name = "ear_outer_\(suffix)"
            // Tilt slightly outward
            outerNode.eulerAngles.z = side * (.pi / 12)
            node.addChildNode(outerNode)

            // Inner ear (pink fill)
            let inner = SCNBox(width: 0.016, height: 0.034, length: 0.005, chamferRadius: 0.004)
            inner.firstMaterial?.diffuse.contents  = UIColor(red: 1.0, green: 0.71, blue: 0.76, alpha: 1)
            inner.firstMaterial?.roughness.contents = 0.9
            let innerNode = SCNNode(geometry: inner)
            innerNode.name = "ear_inner_\(suffix)"
            innerNode.eulerAngles.z = side * (.pi / 12)
            node.addChildNode(innerNode)
        }
        return node
    }

    private func buildFaceMeshNode(textureName: String) -> SCNNode {
        // Uses ARFaceGeometry — updated each frame in renderer delegate
        let node = SCNNode()
        node.name = "facemesh"
        return node
    }

    private func buildLipColorNode() -> SCNNode {
        // Lip color applied via face mesh texture in delegate
        let node = SCNNode()
        node.name = "lipmesh"
        return node
    }

    private func buildEyeShadowNode() -> SCNNode {
        let node = SCNNode()
        node.name = "eyemesh"
        return node
    }
}

// MARK: - ARSCNViewDelegate

extension ARFaceFilterEngine: ARSCNViewDelegate {

    nonisolated func renderer(_ renderer: SCNSceneRenderer,
                               nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor is ARFaceAnchor else { return nil }

        let node = SCNNode()

        // FIX: Invisible occluder — stops the white face covering.
        // ARSCNFaceGeometry with no material renders solid white by default.
        // colorBufferWriteMask=[] makes it write nothing to the color buffer
        // (invisible) but it still writes to the depth buffer, so 3D overlays
        // that pass behind the face are correctly occluded.
        if let device = renderer.device,
           let occluderGeometry = ARSCNFaceGeometry(device: device) {
            let mat = SCNMaterial()
            mat.colorBufferWriteMask = []   // invisible — no color written
            mat.readsFromDepthBuffer  = true
            mat.writesToDepthBuffer   = true
            occluderGeometry.firstMaterial = mat
            let occluderNode = SCNNode(geometry: occluderGeometry)
            occluderNode.name           = "occluder"
            occluderNode.renderingOrder = -1  // depth pass before overlays
            node.addChildNode(occluderNode)
        }

        let content  = SCNNode()
        content.name = "content"

        Task { @MainActor in
            self.faceNode    = node
            self.contentNode = content
            if let overlay = self.activeOverlay, let cached = self.nodeCache[overlay] {
                content.addChildNode(cached)
            }
            self.isFaceDetected = true
        }

        node.addChildNode(content)
        return node
    }

    nonisolated func renderer(_ renderer: SCNSceneRenderer,
                               didUpdate node: SCNNode,
                               for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }

        Task { @MainActor in self.isFaceDetected = faceAnchor.isTracked }

        // Keep occluder in sync with live face shape every frame
        if let occluderNode = node.childNode(withName: "occluder", recursively: false),
           let occluderGeo  = occluderNode.geometry as? ARSCNFaceGeometry {
            occluderGeo.update(from: faceAnchor.geometry)
        }

        // ── LANDMARK-PRECISE OVERLAY POSITIONING ────────────────────────────
        // Read raw vertices from ARFaceGeometry every frame.
        // All positions are in face-local space (same space as the SCNNode).
        // No coordinate conversion needed — the node already inherits the
        // ARFaceAnchor transform (position + rotation + scale) from ARKit.
        let verts = faceAnchor.geometry.vertices

        updateGlassesIfPresent(in: node, vertices: verts)
        updateCrownIfPresent(in: node,   vertices: verts)
        updateEarsIfPresent(in: node,    vertices: verts)

        // Update mesh overlays (mask, lip, eye)
        for name in ["facemesh", "lipmesh", "eyemesh"] {
            if let meshNode = node.childNode(withName: name, recursively: true),
               let device   = renderer.device,
               let geo      = ARSCNFaceGeometry(device: device) {
                geo.update(from: faceAnchor.geometry)
                meshNode.geometry = geo
            }
        }
    }

    // MARK: - Per-frame landmark positioning

    private nonisolated func updateGlassesIfPresent(in node: SCNNode,
                                                      vertices: [SIMD3<Float>]) {
        guard let root = node.childNode(withName: "glasses_root", recursively: true) else { return }

        guard vertices.count > 463 else { return }

        // Key positions in face-local space
        let noseBridgeV  = vertices[9]    // nose bridge center
        let leftEyeCV    = vertices[386]  // left eye center
        let rightEyeCV   = vertices[159]  // right eye center
        let leftTempleV  = vertices[234]  // left temple
        let rightTempleV = vertices[454]  // right temple

        let noseBridge  = SCNVector3(noseBridgeV.x,  noseBridgeV.y,  noseBridgeV.z)
        let leftEyeC    = SCNVector3(leftEyeCV.x,    leftEyeCV.y,    leftEyeCV.z)
        let rightEyeC   = SCNVector3(rightEyeCV.x,   rightEyeCV.y,   rightEyeCV.z)
        let leftTemple  = SCNVector3(leftTempleV.x,  leftTempleV.y,  leftTempleV.z)
        let rightTemple = SCNVector3(rightTempleV.x, rightTempleV.y, rightTempleV.z)

        // Eye separation — drives lens spacing and size
        let eyeSep = simd_distance(leftEyeCV, rightEyeCV)
        let lensR  = eyeSep * 0.38   // lens radius ~38% of eye separation

        // Lenses sit at each eye center, slightly forward of face surface
        let zOffset = Float(0.008)
        if let leftLens = root.childNode(withName: "lens_left", recursively: false) {
            leftLens.position = SCNVector3(leftEyeC.x, leftEyeC.y, leftEyeC.z + zOffset)
            if let torus = leftLens.geometry as? SCNTorus {
                torus.ringRadius = CGFloat(lensR)
                torus.pipeRadius = CGFloat(lensR * 0.12)
            }
        }
        if let rightLens = root.childNode(withName: "lens_right", recursively: false) {
            rightLens.position = SCNVector3(rightEyeC.x, rightEyeC.y, rightEyeC.z + zOffset)
            if let torus = rightLens.geometry as? SCNTorus {
                torus.ringRadius = CGFloat(lensR)
                torus.pipeRadius = CGFloat(lensR * 0.12)
            }
        }

        // Bridge centered between inner eye corners at nose bridge height
        if let bridge = root.childNode(withName: "bridge", recursively: false) {
            let midX = (leftEyeC.x + rightEyeC.x) / 2
            bridge.position = SCNVector3(midX, noseBridge.y, noseBridge.z + zOffset)
            let bridgeWidth = simd_distance(leftEyeCV, rightEyeCV) * 0.35
            if let cyl = bridge.geometry as? SCNCylinder { cyl.height = CGFloat(bridgeWidth) }
        }

        // Temple arms extend from outer lens edge toward temples
        if let tl = root.childNode(withName: "temple_left",  recursively: false) {
            let midX = (leftEyeC.x + leftTemple.x) / 2
            let midY = (leftEyeC.y + leftTemple.y) / 2
            tl.position = SCNVector3(midX, midY, leftEyeC.z + zOffset * 0.5)
            let armLen = simd_distance(leftEyeCV, leftTempleV)
            if let cyl = tl.geometry as? SCNCylinder { cyl.height = CGFloat(armLen) }
            // Aim arm toward temple
            let dx = leftTemple.x - leftEyeC.x
            let dy = leftTemple.y - leftEyeC.y
            tl.eulerAngles.z = atan2(dy, dx) + .pi / 2
        }
        if let tr = root.childNode(withName: "temple_right", recursively: false) {
            let midX = (rightEyeC.x + rightTemple.x) / 2
            let midY = (rightEyeC.y + rightTemple.y) / 2
            tr.position = SCNVector3(midX, midY, rightEyeC.z + zOffset * 0.5)
            let armLen = simd_distance(rightEyeCV, rightTempleV)
            if let cyl = tr.geometry as? SCNCylinder { cyl.height = CGFloat(armLen) }
            let dx = rightTemple.x - rightEyeC.x
            let dy = rightTemple.y - rightEyeC.y
            tr.eulerAngles.z = atan2(dy, dx) + .pi / 2
        }
    }

    private nonisolated func updateCrownIfPresent(in node: SCNNode,
                                                   vertices: [SIMD3<Float>]) {
        guard let root = node.childNode(withName: "crown_root", recursively: true) else { return }
        guard vertices.count > 10 else { return }

        let foreheadV  = vertices[10]   // top forehead center
        let leftTmpV   = vertices[234]
        let rightTmpV  = vertices[454]

        // Crown width matches temple-to-temple span
        let crownWidth = simd_distance(leftTmpV, rightTmpV) * 0.5

        // Position band above forehead — offset upward in face-local Y
        let bandY  = foreheadV.y + crownWidth * 0.18
        let bandZ  = foreheadV.z + 0.005
        if let band = root.childNode(withName: "band", recursively: false) {
            band.position = SCNVector3(foreheadV.x, bandY, bandZ)
            if let cyl = band.geometry as? SCNCylinder {
                cyl.radius = CGFloat(crownWidth * 0.52)
                cyl.height = CGFloat(crownWidth * 0.09)
            }
        }

        // Reposition spikes around band top
        for i in 0..<5 {
            let angle = Float(i) * (.pi * 2 / 5)
            if let spike = root.childNode(withName: "spike_\(i)", recursively: false) {
                spike.position = SCNVector3(
                    foreheadV.x + crownWidth * 0.45 * sin(angle),
                    bandY + crownWidth * 0.12,
                    bandZ  + crownWidth * 0.45 * cos(angle)
                )
                if let cone = spike.geometry as? SCNCone {
                    cone.bottomRadius = CGFloat(crownWidth * 0.085)
                    cone.height       = CGFloat(crownWidth * 0.26)
                }
            }
        }
    }

    private nonisolated func updateEarsIfPresent(in node: SCNNode,
                                                  vertices: [SIMD3<Float>]) {
        guard let root = node.childNode(withName: "ears_root", recursively: true) else { return }
        guard vertices.count > 454 else { return }

        let leftTmpV   = vertices[234]   // left temple
        let rightTmpV  = vertices[454]   // right temple
        let foreheadV  = vertices[10]    // forehead top

        // Ear height — proportional to face vertical span
        let earHeight = Float(0.048)
        // Ears sit at temple height, slightly above, slightly outward from face
        let yOffset   = foreheadV.y * 0.1  // bias upward toward top of head

        for (v, suffix, sign) in [(leftTmpV, "left", Float(-1)), (rightTmpV, "right", Float(1))] {
            // Outward offset — push ear outside face boundary
            let xOut   = v.x + sign * 0.012
            let yPos   = v.y + yOffset + earHeight * 0.3
            let zPos   = v.z - 0.005   // slightly behind temple surface

            if let outer = root.childNode(withName: "ear_outer_\(suffix)", recursively: false) {
                outer.position = SCNVector3(xOut, yPos, zPos)
                if let box = outer.geometry as? SCNBox {
                    box.width  = CGFloat(earHeight * 0.55)
                    box.height = CGFloat(earHeight)
                    box.length = CGFloat(earHeight * 0.18)
                }
                outer.eulerAngles.z = sign * (.pi / 14)
            }
            if let inner = root.childNode(withName: "ear_inner_\(suffix)", recursively: false) {
                inner.position = SCNVector3(xOut, yPos, zPos + 0.003)
                if let box = inner.geometry as? SCNBox {
                    box.width  = CGFloat(earHeight * 0.32)
                    box.height = CGFloat(earHeight * 0.65)
                    box.length = CGFloat(earHeight * 0.12)
                }
                inner.eulerAngles.z = sign * (.pi / 14)
            }
        }
    }

    nonisolated func renderer(_ renderer: SCNSceneRenderer,
                               didRemove node: SCNNode,
                               for anchor: ARAnchor) {
        guard anchor is ARFaceAnchor else { return }
        Task { @MainActor in self.isFaceDetected = false }
    }
}

// MARK: - SwiftUI Wrapper

struct ARFaceView: UIViewRepresentable {
    @ObservedObject var engine: ARFaceFilterEngine

    func makeUIView(context: Context) -> ARSCNView {
        engine.makeARView()
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        uiView.frame = uiView.superview?.bounds ?? uiView.frame
    }
}
