import UIKit

/// The viewfinder apps a frame actually comes from.
///
/// A frame on a shot is shot in a director's viewfinder — the focal length and
/// the format come with it, which is the whole point. This app does not try to
/// be one; it offers to open the one he uses.
///
/// **Neither publishes a URL scheme**, so these are the plausible ones and each
/// is offered *only when iOS says it can be opened*. A guess that is wrong makes
/// the entry not appear, which is a great deal better than a button that does
/// nothing.
struct Viewfinders: Identifiable {
    var name: String
    var schemes: [String]
    var id: String { name }

    static let known = [
        Viewfinders(name: "Cadrage", schemes: ["cadrage", "cadrageviewfinder", "com.cadrage.viewfinder"]),
        Viewfinders(name: "FindErKit", schemes: ["finderkit", "findErKit", "artemis"]),
    ]

    static var installed: [Viewfinders] {
        known.filter { $0.url != nil }
    }

    var url: URL? {
        for scheme in schemes {
            if let url = URL(string: "\(scheme)://"), UIApplication.shared.canOpenURL(url) {
                return url
            }
        }
        return nil
    }

    func open() {
        guard let url else { return }
        UIApplication.shared.open(url)
    }
}
