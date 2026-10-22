import AppKit
import SceneKit
import SwiftUI

/// A scanned room, in a window of its own: turn it over, or measure it flat.
///
/// **Two ways, not three.** Cadrage offers a first-person walk-through as well
/// and he ruled it out — *"skip walk mode, i don't care about it"* (Ref 133) —
/// so what is here is the pair that answer real questions: **the room**, for
/// recognising the place, and **the plan**, for planning in it.
///
/// A window rather than a sheet, for the viewer's reason: it can live on the
/// second monitor and stay there while the shot list is worked on the first.
final class ScanWindow: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ScanWindow()
    private var window: NSWindow?
    private var hosting: NSHostingView<ScanContent>?

    /// **Pinned means it floats above the app**, the same word the other two
    /// pop-outs use for the same button. This window has nothing to follow —
    /// a scan is a file you asked for, not a selection that moves under you —
    /// so pinning it is the half that means something here: hold the floor
    /// plan up while you work the list underneath it.
    @Published var pinned = false {
        didSet {
            guard let window else { return }
            if pinned {
                window.parent?.removeChildWindow(window)
                window.level = .floating
            } else {
                window.level = .normal
                if window.parent == nil { adopt(window) }
            }
        }
    }

    private func adopt(_ w: NSWindow) {
        if let main = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "main" && $0.isVisible
        }) ?? NSApp.windows.first(where: { $0.isVisible && $0 != w }) {
            main.addChildWindow(w, ordered: .above)
            if w.frame.origin == .zero { w.center() }
        }
    }

    func show(usdz: URL, json: URL, title: String, state: ShellState,
              sample: Bool = false, opening: ScanContent.Mode? = nil) {
        let view = ScanContent(usdz: usdz, json: json, title: title,
                               state: state, sample: sample, opening: opening)
        if let hosting {
            hosting.rootView = view
        } else {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
                styleMask: [.titled, .closable, .resizable, .miniaturizable,
                            .fullSizeContentView],
                backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 520, height: 420)
            w.delegate = self
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.identifier = NSUserInterfaceItemIdentifier("scan")
            let host = NSHostingView(rootView: view)
            w.contentView = host
            hosting = host
            if !Launch.checking { w.setFrameAutosaveName("scanWindow") }
            adopt(w)
            window = w
        }
        window?.title = title
        window?.makeKeyAndOrderFront(nil)
        if Launch.checking {
            let plan = sample ? Plan.sample(from: state.engine)
                              : Plan.read(json, from: state.engine)
            FileHandle.standardError.write(Data((
                "scan: \(title)  measured: \(plan != nil)"
                + "  walls: \(plan?.walls.count ?? 0)"
                + "  items: \(plan?.items.count ?? 0)\n").utf8))
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        hosting = nil
    }
}

struct ScanContent: View {
    let usdz: URL
    let json: URL
    let title: String
    @ObservedObject var state: ShellState
    /// Draw the hand-built sample room rather than a file — the only way to
    /// check the drawing on a machine with no LiDAR in it.
    var sample: Bool = false
    /// Which half to open on, when a checking run has asked for one. Nil means
    /// "whichever he was last looking at".
    var opening: Mode? = nil

    enum Mode: String, CaseIterable, Identifiable {
        case room = "3D Scan"
        case plan = "Floor Plan"
        var id: String { rawValue }
        var icon: String { self == .room ? "rotate.3d" : "square.split.bottomrightquarter" }
    }

    // The floor plan is the half that does real work, so it is what opens.
    //
    // **Not `@AppStorage`.** That writes straight to `UserDefaults.standard`
    // and would step round `Remembering`, which is the one thing that keeps a
    // checking run from editing his own settings. A night of checks once
    // pointed his last-opened project at a deleted temp folder; the rule that
    // came out of it is that nothing a check does may be visible to him
    // afterwards, and a preference is visible.
    @State private var mode: Mode = .plan
    @ObservedObject private var scans = ScanWindow.shared
    @State private var plan: Plan?
    @State private var read = false
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            bar
            Group {
                switch mode {
                case .room:
                    if FileManager.default.fileExists(atPath: usdz.path) {
                        Orbit(usdz: usdz, dark: dark)
                    } else {
                        noShape
                    }
                case .plan:
                    if let plan {
                        FloorPlanView(plan: plan)
                    } else {
                        unmeasured
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Brand.surface(dark))
        .buttonStyle(.capsule)
        .task {
            mode = opening ?? Mode(rawValue: Remembering().string(forKey: "scan.mode") ?? "")
                ?? .plan
            plan = sample ? Plan.sample(from: state.engine)
                          : Plan.read(json, from: state.engine)
            read = true
        }
        .onChange(of: mode) { _, fresh in
            Remembering().set(fresh.rawValue, forKey: "scan.mode")
        }
    }

    /// **The same bar the other two pop-outs wear** — `PopoutBar`. It was a
    /// near-copy of the viewer's already; what it never had was the drag, so
    /// this window's drawn bar could not move its own window, and it had no
    /// pin at all.
    private var bar: some View {
        PopoutBar(title: title) {
            // A choice, words only — soft fill, not the top bar's colour.
            Segmented(selection: $mode, items: Mode.allCases.map {
                .init(value: $0, title: $0.rawValue)
            }, quiet: true)
            .fixedSize()
            ToolButton(icon: scans.pinned ? "pin.fill" : "pin", size: 11,
                       help: scans.pinned
                           ? "Pinned"
                           : "Pin it, and it floats above the app",
                       lit: scans.pinned) {
                scans.pinned.toggle()
            }
            // **Both halves are offered**, because they are for different
            // people: the room goes to anyone with a phone, the measurements go
            // to a designer or an art department who will do arithmetic on
            // them. The phone thread's point, and it is right.
            ToolMenu(help: "More") {
                Button("Show scan in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([usdz])
                }
                Button("Show measurements in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([json])
                }
                .disabled(!FileManager.default.fileExists(atPath: json.path))
                Divider()
                Button("Open in another app") { NSWorkspace.shared.open(usdz) }
            }
        }
    }

    /// **Half a scan is said out loud rather than drawn.** The shape survives
    /// without its measurements and still opens; the plan cannot be built from
    /// it at all, and drawing an approximation would be worse than drawing
    /// nothing. The phone thread's rule, kept.
    private var unmeasured: some View {
        VStack(spacing: 8) {
            // Both apps say this, so both read it from `shared/Words.swift`
            // rather than each keeping a copy — Ref 181.
            Text(read ? Words.noMeasurements : "Reading the room…")
                .sans(13, weight: .medium).foregroundStyle(Brand.ink2(dark))
            if read {
                Text(Words.noMeasurementsWhy)
                    .sans(11).foregroundStyle(Brand.ink3(dark))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                Button("Show the 3D scan") { mode = .room }
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The other half missing, said the same way round.
    private var noShape: some View {
        VStack(spacing: 8) {
            Text("No room to turn over").sans(13, weight: .medium)
                .foregroundStyle(Brand.ink2(dark))
            Text("No shape data")
                .sans(11).foregroundStyle(Brand.ink3(dark))
            Button("Show the floor plan") { mode = .plan }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The room as a shape you can turn over.
///
/// SceneKit rather than QuickLook, because QuickLook insists on being the whole
/// window and this has to live under a mode switcher.
private struct Orbit: NSViewRepresentable {
    let usdz: URL
    let dark: Bool

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = (try? SCNScene(url: usdz)) ?? SCNScene()
        Self.prepare(scene)
        view.scene = scene
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = dark ? NSColor(white: 0.06, alpha: 1)
                                    : NSColor(white: 0.97, alpha: 1)
        // A turntable, not a free-flying camera: a room has an up, and letting
        // it roll over produces a picture nobody can read.
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.pointOfView = Self.eye(on: scene)
        return view
    }

    /// **A room opens facing a wall unless somebody puts the camera outside
    /// it.** SceneKit's default camera sits at the origin looking down −Z, and
    /// the origin of a scanned room is *inside the room* — so the first frame is
    /// a flat grey rectangle with no depth in it, which is exactly what this
    /// showed until it was photographed.
    ///
    /// This puts the eye above the room and off one corner, at a distance taken
    /// from the room's own size, looking at its middle. It is the view an
    /// architect's model is photographed from, and it reads as a room in the
    /// first frame.
    static func eye(on scene: SCNScene) -> SCNNode {
        let (low, high) = scene.rootNode.boundingBox
        let middle = SCNVector3((low.x + high.x) / 2, (low.y + high.y) / 2, (low.z + high.z) / 2)
        let size = max(high.x - low.x, max(high.y - low.y, high.z - low.z))
        // Distance is arithmetic, not taste: at SceneKit's default 60° field of
        // view a thing of width w fits at about 0.87w, and the eye sits off two
        // axes, so the per-axis reach is a fraction of that. 1.5 was the first
        // guess and put the room in the middle of a lot of black.
        let reach = CGFloat(max(size, 1)) * 0.7

        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = Double(reach) * 10
        let node = SCNNode()
        node.camera = camera
        node.position = SCNVector3(CGFloat(middle.x) + reach,
                                   CGFloat(middle.y) + reach * 0.9,
                                   CGFloat(middle.z) + reach)
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

    func updateNSView(_ view: SCNView, context: Context) {
        view.backgroundColor = dark ? NSColor(white: 0.06, alpha: 1)
                                    : NSColor(white: 0.97, alpha: 1)
    }
}
