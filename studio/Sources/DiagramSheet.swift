import Foundation

/// What a Diagram page is of: a scene, or a loose plan (`DiagramPlans`).
struct DiagramSheet {
    var id: String
    var heading: String
    var file: String

    init(_ scene: ViewModel.Scene) {
        id = scene.id
        heading = "\(scene.number)  \(scene.heading)"
        file = "Scene \(scene.number) Diagram"
    }

    init(plan id: String, name: String) {
        self.id = id
        heading = name
        file = name
    }
}
