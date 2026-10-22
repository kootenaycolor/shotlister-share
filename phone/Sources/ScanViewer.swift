import SwiftUI
import SceneKit

/// Looking at a scanned room, two ways.
///
/// Cadrage offers three; the third is a first-person walk-through and he does
/// not want it — *"skip walk mode, i don't care about it"* — so it is not here.
/// What is here is the pair that answer real questions: **Orbit**, for
/// recognising the place, and **Floor plan**, for planning in it.
struct ScanViewer: View {
    /// What is open, as one value — presenting a sheet wants a single item.
    struct Opening: Identifiable, Hashable {
        var usdz: URL
        var json: URL
        var title: String
        var id: String { usdz.path }
    }

    let usdz: URL
    let json: URL
    let title: String

    enum Mode: String, CaseIterable, Identifiable {
        case orbit = "Orbit"
        case plan = "Floor Plan"
        var id: String { rawValue }
        var symbol: String { self == .orbit ? "rotate.3d" : "square.split.bottomrightquarter" }
    }

    // The floor plan is what he called most important, so it is what opens.
    @AppStorage("scan.mode") private var mode: Mode = .plan
    @EnvironmentObject private var session: Session
    @State private var plan: Plan?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .orbit:
                    Orbit(usdz: usdz).ignoresSafeArea(edges: .bottom)
                case .plan:
                    if let plan {
                        FloorPlanView(plan: plan)
                    } else {
                        ContentUnavailableView {
                            // Both apps say this, so both read it from
                            // `shared/Words.swift` rather than each keeping a
                            // copy that drifts from the other.
                            Label(Words.noMeasurements, systemImage: "ruler")
                        } description: {
                            Text(Words.noMeasurementsWhy)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { m in
                            Label(m.rawValue, systemImage: m.symbol).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem(placement: .topBarTrailing) { export }
            }
            .task { plan = session.floorPlan(of: json) }
        }
    }

    /// Both halves are offered, because they are for different people: the
    /// `.usdz` goes to anyone with a phone, the measurements go to a designer or
    /// an art department who will do arithmetic with them.
    private var export: some View {
        Menu {
            ShareLink("The room (.usdz)", item: usdz)
            ShareLink("The measurements (.json)", item: json)
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
    }
}

/// The room as a shape you can turn over. SceneKit rather than QuickLook,
/// because QuickLook insists on being the whole screen and this has to live
/// under a mode switcher.
struct Orbit: UIViewRepresentable {
    let usdz: URL

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .systemBackground
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true

        guard let scene = try? SCNScene(url: usdz) else { return view }
        Orbit.prepare(scene)
        scene.rootNode.addChildNode(Orbit.eye(on: scene))
        view.scene = scene
        return view
    }

    /// **Where the eye starts.**
    ///
    /// `allowsCameraControl` with no camera in the scene puts SceneKit's default
    /// one at the origin looking down −Z — and the origin of a scanned room is
    /// *inside the room*, so the first frame is a flat grey wall with no depth
    /// in it. Found by the Mac thread, which photographed exactly that.
    ///
    /// This puts the eye above the room and off one corner, at a distance taken
    /// from the room's own size, looking at its middle: the view an architect's
    /// model is photographed from.
    static func eye(on scene: SCNScene) -> SCNNode {
        let (low, high) = scene.rootNode.boundingBox
        let middle = SCNVector3((low.x + high.x) / 2, (low.y + high.y) / 2, (low.z + high.z) / 2)
        let size = max(high.x - low.x, max(high.y - low.y, high.z - low.z))
        // Arithmetic, not taste: at SceneKit's default 60° field of view a thing
        // of width w fits at about 0.87w, and the eye sits off two axes.
        let reach = max(size, 1) * 0.7

        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = Double(reach) * 10
        let node = SCNNode()
        node.camera = camera
        node.position = SCNVector3(middle.x + reach, middle.y + reach * 0.9, middle.z + reach)
        node.look(at: middle)
        return node
    }

    /// **Walls are single planes, and a plane seen from behind is not there.**
    /// Looking into a scanned room from outside means looking at the *backs* of
    /// the far walls, so half the room disappears unless every surface is drawn
    /// from both sides.
    static func prepare(_ scene: SCNScene) {
        scene.rootNode.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { $0.isDoubleSided = true }
        }
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}
