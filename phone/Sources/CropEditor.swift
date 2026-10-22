import SwiftUI

/// **Framing a picture** — his ask, 2026-08-30: *"allow me to adjust crop and
/// what part of the image is cropped for different aspect ratio."*
///
/// A wall of squares, a table cell, a storyboard plate — all of them take a
/// picture that is not that shape and keep the middle, which is the wrong half
/// of a photograph about as often as it is the right one. This says which half.
///
/// The model is the one every phone already uses: the picture sits behind a
/// window of the shape it will be drawn in, and you move the picture rather
/// than the window. Drag to move, pinch to come in closer. Nothing is written
/// until Done, and the file is never touched at all — what is stored is two
/// numbers and a scale against *this use* of the picture, exactly like a clip's
/// trim.
struct CropEditor: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    let still: Engine.Still
    let image: UIImage
    /// The shape it is being framed for — 1 for a square wall, the film's own
    /// ratio for everything else.
    let shape: Double

    @State private var framing = Engine.Framing.middle
    /// Where the framing stood when this drag or pinch began, so the picture
    /// follows the thumb rather than jumping to it.
    @State private var held: Engine.Framing?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                window
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Button("Reset") {
                        withAnimation(.snappy) { framing = .middle }
                    }
                    .disabled(framing.isMiddle)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if framing.isMiddle {
                            session.clearCrop(still)
                        } else {
                            session.crop(still, x: framing.x, y: framing.y, scale: framing.scale)
                        }
                        dismiss()
                    }
                }
            }
        }
        .onAppear { framing = still.framing }
    }

    // ---- the window ---------------------------------------------------------

    private var window: some View {
        GeometryReader { space in
            let box = fitting(space.size)
            Framed(image: image, framing: framing)
                .frame(width: box.width, height: box.height)
                .clipped() // A picture is never rounded (his rule, 2026-10-07).
                .overlay {
                    // Thirds, because a frame is judged against them and this
                    // is a cinematographer's app.
                    Thirds()
                        .stroke(.white.opacity(0.45), lineWidth: 0.5)
                        .frame(width: box.width, height: box.height)
                }
                .frame(width: space.size.width, height: space.size.height)
                .contentShape(Rectangle())
                .gesture(drag(in: box))
                .simultaneousGesture(pinch)
        }
        .aspectRatio(shape, contentMode: .fit)
        .padding(.horizontal, 16)
    }

    /// The biggest box of the wanted shape that fits the space it is given.
    private func fitting(_ space: CGSize) -> CGSize {
        let byWidth = CGSize(width: space.width, height: space.width / shape)
        if byWidth.height <= space.height { return byWidth }
        return CGSize(width: space.height * shape, height: space.height)
    }

    /// Moving the picture behind the window.
    ///
    /// **Dragging right shows more of the left**, which is what moving a
    /// photograph under a window does — so the anchor goes down as the thumb
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
                    next.x = (from.x - Double(move.translation.width / over.width)).clamped()
                }
                if over.height > 0.5 {
                    next.y = (from.y - Double(move.translation.height / over.height)).clamped()
                }
                framing = next
            }
            .onEnded { _ in held = nil }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { zoom in
                let from = held ?? framing
                if held == nil { held = from }
                var next = from
                next.scale = min(max(from.scale * zoom.magnification, 1), 8)
                framing = next
            }
            .onEnded { _ in held = nil }
    }

    /// How much of the picture hangs over the edges of the window at this
    /// scale — the distance the anchor's nought-to-one actually spans.
    private func overflow(in box: CGSize, scale: Double) -> CGSize {
        let picture = max(image.size.width, 1) / max(image.size.height, 1)
        var width = box.width
        var height = box.width / picture
        if height < box.height {
            height = box.height
            width = height * picture
        }
        return CGSize(width: width * scale - box.width, height: height * scale - box.height)
    }
}

/// The rule of thirds, drawn over the window.
private struct Thirds: Shape {
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

private extension Double {
    func clamped() -> Double { min(max(self, 0), 1) }
}
