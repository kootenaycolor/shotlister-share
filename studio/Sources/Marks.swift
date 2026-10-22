import SwiftUI

/// **The film's own icon and colour, and where they come from.**
///
/// His call, 2026-09-11, after his other Mac drew every film with no icon and
/// the program's plain blue: *"these icons and accent colors can be linked to a
/// project from the project console, but if not, they can be set manually for
/// any project not in the larger system"* — and, on where they should live,
/// *"why can't it be part of the project file data that syncs?"*
///
/// So there are two ways a film gets a mark and one place it is kept:
///
/// - **Linked** to one of his Notion projects: the Mac mirrors that row's icon
///   and colour into the film once (`ShellState.mirrorTheConsole`), and keeps
///   it current whenever the row changes.
/// - **Not linked** — a film that is not in the larger system: he picks one
///   here, out of the marks below.
///
/// Either way it is stored on the film's own record and travels with the film,
/// so a Mac that has never run his Projects Console — which is the whole fault
/// this fixes — still draws the film correctly.
///
/// This file holds the vocabulary: the two words the engine stores, the marks
/// he can pick from, and the colours they come in. The drawing is `Mark.swift`.
enum Marks {
    /// Mirrored off his Notion row, and refreshed when that row changes.
    static let fromConsole = "console"
    /// His own choice. Nothing automatic touches it again.
    static let byHand = "hand"

    enum Source {
        case console, hand, unsaid

        /// Whether the console is allowed to write over what is there. Only his
        /// own hand stops it — the same rule the engine keeps, said here so a
        /// view can ask without a round trip.
        var mirrorable: Bool { self != .hand }
    }

    static func source(_ said: String) -> Source {
        switch said {
        case fromConsole: return .console
        case byHand: return .hand
        default: return .unsaid
        }
    }

    // ---- reading one off a film without opening it --------------------------

    /// **A film's mark, out of its manifest.**
    ///
    /// The project switcher draws a row per film and must not open eleven
    /// documents to do it — so the pair is written on the outside of the
    /// package as well as inside it, and this is that copy. The engine keeps the
    /// two in step (`storage`'s `refresh_manifest`); nothing here writes.
    ///
    /// Nothing for a film whose manifest predates this — which reads exactly the
    /// same as a film with no icon, and is what every film looked like before.
    static func inPackage(at url: URL) -> Console.Mark? {
        struct Manifest: Decodable {
            var markPath: String?
            var markColour: String?
        }
        guard let bytes = try? Data(contentsOf: url.appending(path: "manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: bytes),
              let path = manifest.markPath, !path.isEmpty,
              let colour = manifest.markColour, !colour.isEmpty else { return nil }
        return Console.Mark(path: path, colour: colour)
    }

    // ---- what he can pick from ---------------------------------------------

    /// **Our own drawings, in the icon's own twenty-by-twenty space** — the same
    /// space a Notion icon arrives in, so one drawing routine serves both and a
    /// hand-picked mark sits at exactly the size a mirrored one does.
    ///
    /// Plain shapes on purpose. These stand at thirteen points in a top bar,
    /// where anything with detail in it is a smudge; and a film that is in the
    /// larger system gets its real Notion icon anyway, so this is the set for
    /// the quick job that is not.
    struct Shape: Identifiable, Hashable {
        /// What the tooltip says. A label names the thing.
        let name: String
        let path: String
        var id: String { name }
    }

    static let shapes: [Shape] = [
        Shape(name: "Circle",
              path: "M10 4A6 6 0 1 0 10 16A6 6 0 1 0 10 4Z"),
        Shape(name: "Square",
              path: "M6 3H14A3 3 0 0 1 17 6V14A3 3 0 0 1 14 17H6A3 3 0 0 1 3 14V6A3 3 0 0 1 6 3Z"),
        Shape(name: "Triangle",
              path: "M10 3L17 16H3Z"),
        Shape(name: "Diamond",
              path: "M10 2L18 10L10 18L2 10Z"),
        Shape(name: "Star",
              path: "M10 2L11.88 7.41L17.61 7.53L13.04 10.99L14.7 16.47L10 13.2"
                  + "L5.3 16.47L6.96 10.99L2.39 7.53L8.12 7.41Z"),
        Shape(name: "Hexagon",
              path: "M10 2L16.93 6V14L10 18L3.07 14V6Z"),
        Shape(name: "Cross",
              path: "M8 3H12V8H17V12H12V17H8V12H3V8H8Z"),
        Shape(name: "Arrow",
              path: "M10 3L18 11H14V17H6V11H2Z"),
        Shape(name: "Bars",
              path: "M3 5H7V17H3ZM8 3H12V17H8ZM13 8H17V17H13Z"),
        Shape(name: "Moon",
              path: "M13 3A8 8 0 1 0 13 17A6.5 6.5 0 1 1 13 3Z"),
        Shape(name: "Drop",
              path: "M10 2C10 2 16 9 16 12.5A6 6 0 1 1 4 12.5C4 9 10 2 10 2Z"),
        Shape(name: "Frame",
              path: "M2 5H18V15H2Z"),
    ]

    /// **Notion's own rendered colours**, so a film he colours here sits beside
    /// a film that came from a Notion row without one of them looking wrong.
    /// Taken from what the console's cache actually holds for his projects —
    /// `#D44C47` and not the paler `#e03e3e` the row carries.
    struct Hue: Identifiable, Hashable {
        let name: String
        let hex: String
        var id: String { hex }
    }

    static let hues: [Hue] = [
        Hue(name: "Red", hex: "#D44C47"),
        Hue(name: "Orange", hex: "#D9730D"),
        Hue(name: "Yellow", hex: "#CB912F"),
        Hue(name: "Green", hex: "#448361"),
        Hue(name: "Blue", hex: "#337EA9"),
        Hue(name: "Purple", hex: "#9065B0"),
        Hue(name: "Pink", hex: "#C14C8A"),
        Hue(name: "Brown", hex: "#9F6B53"),
        Hue(name: "Gray", hex: "#787774"),
    ]

    /// The colour a film gets when he picks a shape before picking a colour.
    static let firstHue = "#337EA9"

    /// `#D44C47` from anything near enough to it, and nothing from anything
    /// else. The engine refuses what it cannot draw; this is the same rule on
    /// the near side, so a control never sends something that will be refused.
    static func colour(_ said: String) -> String? {
        let said = said.trimmingCharacters(in: .whitespaces).uppercased()
        guard said.count == 7, said.hasPrefix("#"),
              said.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return said
    }

    /// A colour as six hex digits, from what a colour well hands back. Used by
    /// `FilmsMark` below.
    ///
    /// **Through sRGB, always.** A `Color` from a picker can be in any space the
    /// display uses, and reading its components without converting gives numbers
    /// that are correct for the screen and wrong for everybody else's.
    static func hex(of colour: Color) -> String? {
        guard let converted = NSColor(colour).usingColorSpace(.sRGB) else { return nil }
        let eight = { (part: CGFloat) in Int((part * 255).rounded()) }
        return String(format: "#%02X%02X%02X",
                      eight(converted.redComponent),
                      eight(converted.greenComponent),
                      eight(converted.blueComponent))
    }
}

// ----------------------------------------------- setting one, in the sheet

/// **The film's icon and colour, in Project Settings.**
///
/// One section, under the Notion link, because which half of it is live depends
/// on that link: a film linked to one of his Notion projects wears that row's
/// icon and says so, and a film that is not gets one from here.
///
/// Picking anything here makes it **his** — the mirror never writes over a
/// hand-set mark again. *Take from Notion* undoes that, and is only offered
/// when there is a Notion icon to take.
struct FilmsMark: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    private var project: ViewModel.Project? { state.view?.project }
    private var worn: Console.Mark? { project?.mark }
    private var locked: Bool { project?.readOnly == true }

    /// What his Notion row says, if his Projects Console is on this Mac and has
    /// a row for this film. Read once, in `task` — it is a file on disk.
    @State private var inNotion: Console.Mark?
    @State private var custom = Color.blue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Icon & Color").fieldLabel(dark)
            head
            shapes
            hues
        }
        .task {
            let page = project?.consolePage ?? ""
            let named = project?.title ?? ""
            inNotion = Console.mark(page: page, named: named)
            if let worn { custom = Brand.hex(worn.colour) }
        }
        .disabled(locked)
        .opacity(locked ? 0.5 : 1)
    }

    private var head: some View {
        HStack(spacing: 10) {
            Group {
                if let worn {
                    FilmIcon(mark: worn, size: 20)
                } else {
                    Circle().strokeBorder(Brand.rule2(dark), lineWidth: 1)
                        .frame(width: 20, height: 20)
                }
            }
            Text(said).sans(11).foregroundStyle(Brand.ink3(dark))
            Spacer(minLength: 6)
            // **Only what his own hand can undo.** A film wearing its Notion
            // icon has nothing to put back — clearing it would only fetch the
            // same icon again — so the button is not there to press.
            if worn != nil, Marks.source(project?.markSource ?? "") == .hand {
                Button(inNotion == nil ? "Clear" : "Take from Notion") {
                    state.clearTheMark()
                }
                .buttonStyle(.rowAction)
            }
        }
    }

    /// Three words at most, and each of them names a state rather than
    /// explaining one.
    private var said: String {
        guard worn != nil else { return "None" }
        switch Marks.source(project?.markSource ?? "") {
        case .console: return "From Notion"
        case .hand: return "Set by hand"
        case .unsaid: return ""
        }
    }

    // ---- the marks ---------------------------------------------------------

    private var shapes: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 12),
                  spacing: 6) {
            ForEach(Marks.shapes) { shape in
                let on = shape.path == project?.markPath
                Button {
                    // **A shape picked before a colour comes in a colour**, so
                    // something is drawn the moment he presses it rather than
                    // half a mark that the engine would refuse.
                    state.setTheMark(path: shape.path,
                                     colour: worn?.colour ?? Marks.firstHue)
                } label: {
                    Outline.Shape(d: shape.path)
                        .fill(on ? Brand.hex(worn?.colour ?? Marks.firstHue)
                                 : Brand.ink3(dark))
                        .frame(width: 17, height: 17)
                        .padding(4)
                        .background {
                            RoundedRectangle(cornerRadius: Brand.radiusChip,
                                             style: .continuous)
                                .fill(on ? Brand.accentTint(dark) : Brand.glass2(dark))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Brand.radiusChip,
                                                     style: .continuous)
                                        .strokeBorder(on ? Brand.accentLine(dark)
                                                         : Brand.glassEdge(dark),
                                                      lineWidth: 1)
                                }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(shape.name)
            }
        }
    }

    // ---- the colours -------------------------------------------------------

    /// **Nothing to colour until there is a shape**, so these wait for one. The
    /// order on screen is the order of the two decisions.
    private var hues: some View {
        HStack(spacing: 6) {
            ForEach(Marks.hues) { hue in
                let on = hue.hex == worn?.colour
                Button {
                    state.setTheMark(path: project?.markPath ?? "", colour: hue.hex)
                } label: {
                    Circle()
                        .fill(Brand.hex(hue.hex))
                        .frame(width: 17, height: 17)
                        .overlay {
                            Circle().strokeBorder(
                                on ? Brand.ink(dark) : Brand.glassEdge(dark),
                                lineWidth: on ? 2 : 1)
                        }
                        .padding(2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(hue.name)
            }
            ColorPicker("", selection: $custom, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: custom) { _, now in
                    guard let hex = Marks.hex(of: now), hex != worn?.colour else { return }
                    state.setTheMark(path: project?.markPath ?? "", colour: hex)
                }
                .help("Another colour")
            Spacer(minLength: 0)
        }
        .disabled(worn == nil)
        .opacity(worn == nil ? 0.45 : 1)
    }
}
