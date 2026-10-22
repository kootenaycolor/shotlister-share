import SwiftUI

/// One scene's pages, drawn.
struct ScenePages: View {
    @EnvironmentObject private var session: Session
    let scene: Engine.Scene

    var body: some View {
        Group {
            switch session.script {
            case .none:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .missing(let why):
                ContentUnavailableView {
                    Label("No script", systemImage: "doc.plaintext")
                } description: {
                    Text(why)
                }
            case .read(let script):
                let lines = script.drawn(ofScene: scene.number)
                if lines.isEmpty {
                    ContentUnavailableView {
                        Label("Not in the Script", systemImage: "doc.plaintext")
                    } description: {
                        Text("Scene \(scene.number) is not in \(script.name)")
                    }
                } else {
                    page(lines, measure: script.measure)
                }
            }
        }
    }

    private func page(_ lines: [Script.Drawn], measure: Int) -> some View {
        GeometryReader { space in
            // **The type is sized so the engine's measure fits the width.** The
            // engine has already wrapped every line at the width of a
            // screenplay page; if the phone then wraps them again, the shape
            // that makes a script readable — where a speech ends, how long an
            // action runs — is lost, and it reads as ragged prose.
            let em = (space.size.width - 32) / CGFloat(max(measure, 40))
            let size = min(14, max(7, em / 0.6))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.system(size: size, design: .monospaced))
                            // Greyed, because they are not the writer's and
                            // nobody should read them as dialogue.
                            .foregroundStyle(line.faded ? AnyShapeStyle(.tertiary)
                                                        : AnyShapeStyle(.primary))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(height: size * 1.35, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

}
