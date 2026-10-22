import AppKit
import SwiftUI

/// **Framing a picture** — his ask, 2026-08-30: *"allow me to adjust crop and
/// what part of the image is cropped for different aspect ratio in images in
/// both ios and mac apps."*
///
/// A wall of squares, a table cell, a storyboard plate: each takes a picture
/// that is not that shape and keeps the middle, which is the wrong half of a
/// photograph about as often as it is the right one.
///
/// The model is the phone's, deliberately — the two apps write the same three
/// numbers to the same record, and a person who has learned one has learned the
/// other. The picture sits behind a window of the shape it will be drawn in and
/// you move the picture, not the window. Nothing is written until Save, and the
/// file is never touched at all.
///
/// **The shape row is a preview, not a setting.** One framing serves every
/// shape the picture is drawn in; the row is here so he can see what the same
/// framing does to a square and to the film's own ratio before he keeps it.
struct CropSheet: View {
    @ObservedObject var state: ShellState
    /// The use of the picture being framed — the media ref, not the file.
    let ref: String
    let picture: NSImage
    let filename: String
    /// Where it started, so Cancel has something to mean.
    let start: ViewModel.Framing

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var framing = ViewModel.Framing.middle
    /// Where the framing stood when this drag began, so the picture follows
    /// the mouse rather than jumping to it.
    @State private var held: ViewModel.Framing?
    @State private var shape: Shape = .project

    enum Shape: String, CaseIterable, Identifiable {
        case project = "Project"
        case square = "Square"
        case wide = "16:9"
        var id: String { rawValue }
    }

    private var ratio: CGFloat {
        switch shape {
        case .project: return CGFloat(state.view?.project.ratio ?? 1.85)
        case .square: return 1
        case .wide: return 16 / 9
        }
    }

    var body: some View {
        Sheet(title: "Crop", subtitle: filename, width: .standard, height: 560, scrolls: false) {
            VStack(spacing: 12) {
                HStack {
                    Segmented(selection: $shape,
                              items: Shape.allCases.map { .init(value: $0, title: $0.rawValue) },
                              quiet: true)
                        .fixedSize()
                    Spacer(minLength: 0)
                }
                window
                HStack(spacing: 10) {
                    Text("How Close").fieldLabel(dark)
                    Slider(value: Binding(get: { framing.scale },
                                          set: { framing.scale = $0 }), in: 1...4)
                        .controlSize(.small)
                    Button("Reset") { framing = .middle }
                        .buttonStyle(.rowAction)
                        .disabled(framing.isMiddle)
                }
            }
            .padding(18)
        } trailing: {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear { framing = start }
    }

    // ---- the window ---------------------------------------------------------

    private var window: some View {
        GeometryReader { space in
            let box = fitting(space.size)
            Framed(picture: picture, framing: framing)
                .frame(width: box.width, height: box.height)
                .overlay {
                    Thirds().stroke(.white.opacity(0.4), lineWidth: 0.5)
                }
                .overlay {
                    Rectangle().strokeBorder(Brand.rule(dark), lineWidth: 1)
                }
                .frame(width: space.size.width, height: space.size.height)
                .contentShape(Rectangle())
                .gesture(drag(in: box))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The biggest box of the wanted shape that fits the space it is given.
    private func fitting(_ space: CGSize) -> CGSize {
        let byWidth = CGSize(width: space.width, height: space.width / ratio)
        if byWidth.height <= space.height { return byWidth }
        return CGSize(width: space.height * ratio, height: space.height)
    }

    /// **Dragging right shows more of the left**, which is what moving a
    /// photograph under a window does — so the anchor goes down as the mouse
    /// goes right. The step is measured against how much of the picture hangs
    /// over the edges, so a big picture moves as far per inch as a small one.
    private func drag(in box: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { move in
                let from = held ?? framing
                if held == nil { held = from }
                let over = overflow(in: box, scale: from.scale)
                var next = from
                if over.width > 0.5 {
                    next.x = min(max(from.x - Double(move.translation.width / over.width), 0), 1)
                }
                if over.height > 0.5 {
                    next.y = min(max(from.y - Double(move.translation.height / over.height), 0), 1)
                }
                framing = next
            }
            .onEnded { _ in held = nil }
    }

    /// How much of the picture hangs over the edges of the window at this
    /// scale — the distance the anchor's nought-to-one actually spans.
    private func overflow(in box: CGSize, scale: Double) -> CGSize {
        let shape = max(picture.size.width, 1) / max(picture.size.height, 1)
        var width = box.width
        var height = box.width / shape
        if height < box.height {
            height = box.height
            width = height * shape
        }
        return CGSize(width: width * scale - box.width, height: height * scale - box.height)
    }

    private func save() {
        guard let engine = state.engine else { return dismiss() }
        // Nothing to remember is worth saying out loud rather than storing:
        // absent is the middle at full width, everywhere in the app.
        if framing.isMiddle {
            state.replace(engine.clearCrop(ref))
        } else {
            state.replace(engine.crop(ref, x: framing.x, y: framing.y, scale: framing.scale))
        }
        dismiss()
    }
}

/// The rule of thirds, drawn over the window — a frame is judged against them.
private struct Thirds: SwiftUI.Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for step in 1...2 {
            let x = rect.minX + rect.width * CGFloat(step) / 3
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            let y = rect.minY + rect.height * CGFloat(step) / 3
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}
