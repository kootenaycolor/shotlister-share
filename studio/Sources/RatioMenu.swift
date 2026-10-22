import AppKit
import SwiftUI

/// The rows of every ratio menu: the presets in their two groups, his own,
/// and `Custom…`.
struct RatioMenuItems: View {
    let current: Double
    let choose: (Double) -> Void
    let typeOne: () -> Void
    @AppStorage(Ratios.key) private var stored = ""

    var body: some View {
        ForEach(Ratios.groups) { group in
            Section(group.title) {
                ForEach(group.presets) { p in
                    row(p.title, p.value)
                }
            }
        }
        let saved = Ratios.custom(stored)
        let own = saved + (Ratios.preset(for: current) == nil
            && !saved.contains { Ratios.same($0, current) } ? [current] : [])
        Section("Custom") {
            ForEach(own, id: \.self) { r in
                row(Ratios.name(r), r)
            }
            Button("Custom…", action: typeOne)
            if !saved.isEmpty {
                Button("Clear Custom Ratios") { stored = "" }
            }
        }
    }

    @ViewBuilder private func row(_ title: String, _ value: Double) -> some View {
        Button { choose(value) } label: {
            if Ratios.same(value, current) {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

/// A ratio menu with whatever face the place it sits in wants — a field in a
/// form, a pill in a bar — and the Custom form hanging off it.
struct FrameRatioMenu<Face: View>: View {
    let current: Double
    let choose: (Double) -> Void
    @ViewBuilder let face: () -> Face
    @State private var typing = false

    var body: some View {
        Menu {
            RatioMenuItems(current: current, choose: choose) { typing = true }
        } label: {
            face()
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .focusEffectDisabled()
        .popover(isPresented: $typing, arrowEdge: .top) {
            CustomRatioForm(save: { r in
                Ratios.remember(r)
                choose(r)
                typing = false
            }, cancel: { typing = false })
        }
    }
}

/// `Custom…`: any frame, typed the way he would say it.
struct CustomRatioForm: View {
    let save: (Double) -> Void
    let cancel: () -> Void
    @State private var said: String
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    init(start: String = "", save: @escaping (Double) -> Void, cancel: @escaping () -> Void) {
        self.save = save
        self.cancel = cancel
        _said = State(initialValue: start)
    }

    private var ratio: Double? { Ratios.parse(said) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom Ratio").sans(Brand.Size.body, weight: .semibold)
            HStack(alignment: .bottom, spacing: 12) {
                Field("Ratio") {
                    FieldText(placeholder: "2.55:1 or 9:16", text: $said) {
                        if let ratio { save(ratio) }
                    }
                }
                frame
            }
            HStack {
                Spacer()
                Button("Cancel") { cancel() }.buttonStyle(.capsule)
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Set") { if let ratio { save(ratio) } }.buttonStyle(.primary)
                    .disabled(ratio == nil)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    /// The frame it makes, small, so a typo shows as a wrong shape before it
    /// reaches a single card.
    private var frame: some View {
        let r = CGFloat(ratio ?? 1)
        let box: CGFloat = 44
        let w = r >= 1 ? box : box * r
        let h = r >= 1 ? box / r : box
        return ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(ratio == nil ? Brand.ink3(dark) : Brand.ink2(dark),
                              style: StrokeStyle(lineWidth: 1, dash: ratio == nil ? [3, 3] : []))
                .frame(width: w, height: h)
        }
        .frame(width: box, height: box)
        .animation(.easeOut(duration: 0.12), value: ratio)
    }
}

/// The checks' way in: `--ratiomenu <path.png>` draws the menu's rows and the
/// Custom form to a file — neither a menu nor a popover is ever in the
/// window's photograph — and says the rows on stderr.
enum RatioDrive {
    @MainActor
    static func photograph(_ path: String, current: Double) {
        var rows: [String] = []
        for g in Ratios.groups {
            rows.append("[\(g.title)]")
            rows += g.presets.map { (Ratios.same($0.value, current) ? "✓ " : "   ") + $0.title }
        }
        rows.append("[Custom]")
        rows += Ratios.custom(UserDefaults.standard.string(forKey: Ratios.key) ?? "").map { "   " + Ratios.name($0) }
        rows.append("   Custom…")
        FileHandle.standardError.write(Data(("ratio menu: " + rows.joined(separator: " | ") + "\n").utf8))
        let page = HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(rows, id: \.self) { Text($0).font(.system(size: 13)) }
            }
            VStack(spacing: 14) {
                CustomRatioForm(start: "9:16", save: { _ in }, cancel: {})
                CustomRatioForm(start: "4096x1716", save: { _ in }, cancel: {})
                CustomRatioForm(start: "wide", save: { _ in }, cancel: {})
            }
        }
        .padding(16)
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
