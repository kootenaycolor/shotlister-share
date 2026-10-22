import AppKit
import SwiftUI

// **The project's frames, in Studio** — stage 5 step 4, piece E (2026-10-15).
//
// His answers 20–21: the frames are written once, on the spec sheet in the
// console (a name and a ratio, one Main for the portal; no resolution).
// Studio keeps its ratio setting, but it becomes a picker over those frames,
// chosen apart from Main, and the others can show as guide lines. The engine
// owns which frame is drawn (`engine/src/frames.rs`); this file only draws
// the menu and the lines.
//
// With no frames on the card (the server's switch off, an older server, no
// card) nothing here shows, and the ratio menu is `FrameRatioMenu` as before.

/// One of the other frames, as a guide line inside the frame Studio draws at.
struct FrameGuide: Hashable {
    var name: String
    var said: String
    var ratio: CGFloat
}

enum FramePicker {
    /// `Delivery  2.39:1 · Main`
    static func title(_ f: ViewModel.ProjectFrame) -> String {
        "\(f.name)  \(f.said)" + (f.main ? " · Main" : "")
    }

    /// The pill's words: the frame's name, else its ratio.
    static func face(_ project: ViewModel.Project?) -> String {
        guard let project, let frames = project.frames else { return Ratios.name(project?.ratio ?? 2.39) }
        let picked = frames.first { $0.picked } ?? frames.first
        return picked.map { "\($0.name)  \($0.said)" } ?? Ratios.name(project.ratio)
    }

    /// The guide lines to draw: every frame but the picked one, while the
    /// guides are on. Empty otherwise.
    static func guides(_ project: ViewModel.Project?) -> [FrameGuide] {
        guard let project, project.frameGuides, let frames = project.frames, frames.count > 1 else { return [] }
        return frames.filter { !$0.picked }.map { FrameGuide(name: $0.name, said: $0.said, ratio: CGFloat($0.ratio)) }
    }

    /// Where a guide sits inside a frame of `ratio` and `size`: the biggest
    /// rectangle of the guide's shape that fits, centred — a wider frame is
    /// two lines across, a taller one two lines down.
    static func rect(_ guide: CGFloat, in ratio: CGFloat, size: CGSize) -> CGRect {
        let g = max(guide, 0.01)
        _ = ratio
        var w = size.width
        var h = size.width / g
        if h > size.height {
            h = size.height
            w = size.height * g
        }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}

/// **The other frames, as guide lines** — dashed, each with its name, drawn
/// over a picture already cut to the picked frame. Fills the space it is
/// given, which is that frame.
struct FrameGuideLines: View {
    let guides: [FrameGuide]
    var ratio: CGFloat
    var labels = true

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(guides, id: \.self) { g in
                    let r = FramePicker.rect(g.ratio, in: ratio, size: geo.size)
                    Rectangle()
                        .strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                    if labels {
                        Text("\(g.name) \(g.said)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.6), radius: 1)
                            .padding(.horizontal, 3).padding(.vertical, 2)
                            .offset(x: r.minX, y: r.minY)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }
}

/// The rows of the frame menu: the project's frames, Show Guides, Edit Aspect Ratios….
struct FramePickerItems: View {
    @ObservedObject var state: ShellState

    var body: some View {
        let project = state.view?.project
        let frames = project?.frames ?? []
        Section("Draw Storyboards At") {
            ForEach(frames) { f in
                Button { pick(f) } label: {
                    if f.picked {
                        Label(FramePicker.title(f), systemImage: "checkmark")
                    } else {
                        Text(FramePicker.title(f))
                    }
                }
            }
        }
        Divider()
        Button { guides(!(project?.frameGuides ?? false)) } label: {
            if project?.frameGuides == true {
                Label("Show Other Aspect Ratios as Guides", systemImage: "checkmark")
            } else {
                Text("Show Other Aspect Ratios as Guides")
            }
        }
        .disabled(frames.count < 2)
        Button("Edit Aspect Ratios…") {
            Console.openProject(page: project?.consolePage ?? "")
        }
    }

    private func pick(_ f: ViewModel.ProjectFrame) {
        guard let engine = state.engine, !f.picked else { return }
        state.replace(engine.pickFrame(f.name))
    }

    private func guides(_ on: Bool) {
        guard let engine = state.engine else { return }
        state.replace(engine.setFrameGuides(on))
    }
}

/// **The frame menu with whatever face the place it sits in wants** — the
/// project's frames when the card brings them, the ratio menu otherwise.
struct ProjectFrameMenu<Face: View>: View {
    @ObservedObject var state: ShellState
    @ViewBuilder let face: () -> Face

    var body: some View {
        if state.view?.project.frames != nil {
            Menu {
                FramePickerItems(state: state)
            } label: {
                face()
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .focusEffectDisabled()
        } else {
            FrameRatioMenu(current: state.view?.project.ratio ?? 2.39, choose: { r in
                guard let engine = state.engine, let project = state.view?.project.id else { return }
                state.replace(engine.set(shot: project, field: "aspect_ratio", value: String(format: "%.4f", r)))
            }, face: face)
        }
    }
}

/// The checks' way in: `--framemenu <path.png>` draws the frame menu's rows
/// (a menu is never in the window's photograph) and says them on stderr.
enum FrameMenuDrive {
    @MainActor
    static func photograph(_ path: String, project: ViewModel.Project?) {
        var rows: [String] = ["[Draw Storyboards At]"]
        for f in project?.frames ?? [] {
            rows.append((f.picked ? "✓ " : "   ") + FramePicker.title(f))
        }
        rows.append("---")
        rows.append((project?.frameGuides == true ? "✓ " : "   ") + "Show Other Aspect Ratios as Guides")
        rows.append("   Edit Aspect Ratios…")
        FileHandle.standardError.write(Data(("frame menu: " + rows.joined(separator: " | ") + "\n").utf8))
        let page = VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if row == "---" { Divider().frame(width: 220) } else { Text(row).font(.system(size: 13)) }
            }
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: page)
        r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}
