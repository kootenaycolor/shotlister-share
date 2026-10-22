import SwiftUI

/// **The project's other frames, as guide lines** — the Mac's, on a card: dashed,
/// each with its name, drawn inside the frame the card is cut to. The rule is
/// `FramePicker.rect` in Studio: the biggest rectangle of the guide's shape
/// that fits, centred.
struct FrameGuide: Hashable {
    var name: String
    var said: String
    var ratio: CGFloat

    /// Every frame but the picked one, while Show Guides is on.
    static func of(_ project: Engine.Project?) -> [FrameGuide] {
        #if targetEnvironment(simulator)
        // A checking run on a scratch copy has no card to bring frames:
        // `-StartGuides 1` draws two.
        if UserDefaults.standard.bool(forKey: "StartGuides") {
            return [FrameGuide(name: "Delivery", said: "2.39:1", ratio: 2.39), FrameGuide(name: "Social", said: "1:1", ratio: 1)]
        }
        #endif
        guard let project, project.frameGuides, let frames = project.frames, frames.count > 1 else { return [] }
        return frames.filter { !$0.picked }.map { FrameGuide(name: $0.name, said: $0.said, ratio: CGFloat($0.ratio)) }
    }

    static func rect(_ guide: CGFloat, size: CGSize) -> CGRect {
        let g = max(guide, 0.01)
        var w = size.width
        var h = size.width / g
        if h > size.height { h = size.height; w = size.height * g }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}

struct FrameGuideLines: View {
    let guides: [FrameGuide]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(guides, id: \.self) { g in
                    let r = FrameGuide.rect(g.ratio, size: geo.size)
                    Rectangle()
                        .strokeBorder(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                    Text("\(g.name) \(g.said)")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.7), radius: 1)
                        .padding(2)
                        .offset(x: r.minX, y: r.minY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }
}
