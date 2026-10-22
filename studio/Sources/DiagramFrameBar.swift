import SwiftUI
import AppKit

// A frame's bar, its swatches, and the plain ink every lamp is drawn in —
// the Diagram's grip and lighting pass of 2026-09-30.

// MARK: - the frame's bar

/// **Material on the bar, one tap** (2026-09-30, his ask: "as good as that
/// one"). It opens a picker of pictures — the skins as swatches of the
/// cloth, nets and silks edged in the colours their rags are bound in
/// (single green, double red, silk gold) — and the button then shows what
/// is on. (Frame Type and Grid went 2026-10-05: a plot draws neither.)
struct DiagramFrameActions: View {
    @ObservedObject var model: DiagramModel
    let e: DiagramEl
    let what: String
    /// Its face alone, for the bar to measure.
    var measuring = false
    @State private var open = false
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @ViewBuilder var body: some View {
        if measuring { face } else { button }
    }

    private var button: some View {
        Button { open.toggle() } label: { face }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .top) {
                materials.padding(12)
            }
    }

    /// The bar's way with a setting (design/26): the quiet word that names
    /// it, then what it is now; the cloth is its swatch and its name.
    @ViewBuilder private var face: some View {
        HStack(spacing: 5) {
            // The word, then the swatch and its name (design/32's bar).
            if let m = DiagramFrames.material(e, model) {
                Text("Material").foregroundStyle(Brand.ink2(dark))
                DiagramSwatch(material: m, gel: e.gels.first).frame(width: 13, height: 13)
                Text(m.id == "gel" ? (e.gels.first.map(DiagramGels.name) ?? m.name) : m.name).fontWeight(.semibold)
            }
        }
        .sans(Brand.Size.body, weight: .medium)
        .foregroundStyle(Brand.ink(dark))
        .lineLimit(1)
        .padding(.horizontal, 8).frame(height: 24)
        .background(Capsule().fill(open ? Brand.glassOn(dark) : .clear))
        .contentShape(Rectangle())
    }

    private func pick(_ set: [String: Any]) {
        model.update([e.id], set)
        open = false
    }

    private var materials: some View {
        let all = DiagramFrames.choices(model)?.materials ?? []
        var groups: [String] = []
        for m in all where !groups.contains(m.group) { groups.append(m.group) }
        let now = e.material.isEmpty ? DiagramFrames.defaultMaterial(model) : e.material
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(groups, id: \.self) { g in
                    Text(g).fieldLabel(dark)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: 5), alignment: .leading, spacing: 8) {
                        ForEach(all.filter { $0.group == g }) { m in
                            if m.id == "gel" {
                                gelTile(m, on: now == "gel")
                            } else {
                                tile(m, on: now == m.id) { pick(["material": m.id]) }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 368, height: 430)
    }

    private func tile(_ m: DiagramFrameChoices.Material, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            VStack(spacing: 4) {
                DiagramSwatch(material: m, gel: nil)
                    .frame(width: 40, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: DiagramInk.pick), lineWidth: on ? 2 : 0).padding(-3))
                Text(m.name).sans(Brand.Size.tiny).foregroundStyle(Brand.ink2(dark))
                    .multilineTextAlignment(.center).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plain)
        .help(m.name)
    }

    /// Gel as the skin: a clear frame in a gel's colour — pick which.
    private func gelTile(_ m: DiagramFrameChoices.Material, on: Bool) -> some View {
        Menu {
            ForEach(DiagramGels.groups, id: \.0) { group, gels in
                Section(group) {
                    ForEach(gels) { g in Button(g.name) { pick(["material": "gel", "gels": [g.id]]) } }
                }
            }
        } label: {
            VStack(spacing: 4) {
                DiagramSwatch(material: m, gel: on ? e.gels.first : "cto-half")
                    .frame(width: 40, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: DiagramInk.pick), lineWidth: on ? 2 : 0).padding(-3))
                Text(on ? (e.gels.first.map(DiagramGels.name) ?? "Gel") : "Gel").sans(Brand.Size.tiny).foregroundStyle(Brand.ink2(dark))
                    .lineLimit(2).frame(width: 64)
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}

/// A skin as a small piece of cloth: its colour, a checkerboard's squares,
/// a net's weave, and the edge it is bound in.
struct DiagramSwatch: View {
    let material: DiagramFrameChoices.Material
    let gel: String?

    var body: some View {
        Canvas { c, size in
            let r = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            let shape = Path(roundedRect: r, cornerRadius: 5)
            if material.id == "gel" {
                c.fill(shape, with: .color(gelColour.opacity(0.75)))
            } else if material.fill.isEmpty {
                // No material: the bare pipe, nothing in it.
                c.fill(shape, with: .color(.white))
                var cross = Path()
                cross.move(to: CGPoint(x: r.minX + 4, y: r.maxY - 4))
                cross.addLine(to: CGPoint(x: r.maxX - 4, y: r.minY + 4))
                c.stroke(cross, with: .color(.gray.opacity(0.6)), lineWidth: 1)
            } else {
                c.fill(shape, with: .color(Brand.hex(material.fill)))
            }
            if !material.alt.isEmpty {
                let n = 4
                let (sw, sh) = (r.width / CGFloat(n), r.height / CGFloat(n))
                var squares = Path()
                for i in 0..<n {
                    for j in 0..<n where (i + j) % 2 == 1 {
                        squares.addRect(CGRect(x: r.minX + CGFloat(i) * sw, y: r.minY + CGFloat(j) * sh, width: sw, height: sh))
                    }
                }
                var inner = c
                inner.clip(to: shape)
                inner.fill(squares, with: .color(Brand.hex(material.alt)))
            }
            if material.id.hasSuffix("-net") {
                var weave = Path()
                for x in stride(from: r.minX + 3, to: r.maxX, by: 3) {
                    weave.move(to: CGPoint(x: x, y: r.minY)); weave.addLine(to: CGPoint(x: x, y: r.maxY))
                }
                for y in stride(from: r.minY + 3, to: r.maxY, by: 3) {
                    weave.move(to: CGPoint(x: r.minX, y: y)); weave.addLine(to: CGPoint(x: r.maxX, y: y))
                }
                var inner = c
                inner.clip(to: shape)
                inner.stroke(weave, with: .color(.black.opacity(material.id == "double-net" ? 0.45 : 0.25)), lineWidth: 0.6)
            }
            let bound = !material.edge.isEmpty
            c.stroke(shape, with: .color(bound ? Brand.hex(material.edge) : Color.black.opacity(0.25)), lineWidth: bound ? 3 : 1)
        }
    }

    private var gelColour: Color {
        let g = gel ?? ""
        if g.hasPrefix("cto") { return Brand.hex("F2A33A") }
        if g.hasPrefix("ctb") { return Brand.hex("5B8FE0") }
        if g.hasPrefix("plus-green") { return Brand.hex("6CC46C") }
        if g.hasPrefix("minus-green") { return Brand.hex("D86CC4") }
        if g.hasPrefix("nd") { return Brand.hex("8C8C8C") }
        return Brand.hex("E6E6E6")
    }
}

// MARK: - plain ink

extension DiagramPictures {
    /// The fill the engine gives a pack picture to be drawn in plain ink
    /// (`symbols::INKED`).
    static let inkedRole = "artink"
    private static var inks: [String: NSImage] = [:]

    /// **A lamp or bit of grip in plain ink** (2026-09-30): the picture's
    /// own light and shade in greys, a touch firmer — the same sums as the
    /// page's `-ink` filter (`svg.rs`): grey by Rec. 709, then 1.25 × − 0.28 (firmer since 2026-10-01).
    static func inked(_ image: NSImage, media: String) -> NSImage {
        if let got = inks[media] { return got }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let (w, h) = (cg.width, cg.height)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Double(px[i + 3])
            guard a > 0 else { continue }
            // Un-premultiplied, greyed, firmed, premultiplied again.
            let r = Double(px[i]) / a, g = Double(px[i + 1]) / a, b = Double(px[i + 2]) / a
            let y = min(max((0.2126 * r + 0.7152 * g + 0.0722 * b) * 1.25 - 0.28, 0), 1)
            let v = UInt8((y * a).rounded())
            px[i] = v; px[i + 1] = v; px[i + 2] = v
        }
        guard let out = ctx.makeImage() else { return image }
        let made = NSImage(cgImage: out, size: image.size)
        inks[media] = made
        return made
    }
}

// MARK: - recently used

/// The pieces put down lately, newest first, by library — the top of each
/// library panel. This Mac's, like the panel's own search.
enum DiagramRecent {
    static let most = 8

    static func ids(in lib: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: "diagramRecent." + lib) ?? []
    }

    static func use(_ id: String, in lib: String) {
        guard !lib.isEmpty else { return }
        var now = ids(in: lib).filter { $0 != id }
        now.insert(id, at: 0)
        UserDefaults.standard.set(Array(now.prefix(most)), forKey: "diagramRecent." + lib)
    }
}
