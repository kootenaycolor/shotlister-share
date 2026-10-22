import Foundation
import MapKit

/// Address suggestions, as he types.
///
/// Apple's own completer, which is what Maps uses — so a half-typed street he
/// half-remembers finds the same answer his phone would find. Kept deliberately
/// simple: it holds a query and a list, and knows nothing about locations.
///
/// **The Mac has one of these too** (`studio/Sources/Locations.swift`), a
/// second copy by design — the two targets share no source folder yet. The
/// two are kept the same by hand; the search fallback landed there on
/// 2026-09-01 and here on 2026-09-11 (Ref 597).
@MainActor
final class AddressLookup: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {

    /// One row in the list. Apple answers an address in two different ways and
    /// they do not know the same places, so a row is either.
    enum Answer: Hashable {
        case suggested(MKLocalSearchCompletion)
        case found(MKMapItem)

        var title: String {
            switch self {
            case .suggested(let it): return it.title
            case .found(let it): return it.name ?? (it.placemark.title ?? "")
            }
        }

        var subtitle: String {
            switch self {
            case .suggested(let it): return it.subtitle
            case .found(let it):
                let mark = it.placemark
                let town = [mark.locality, mark.administrativeArea]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                return [town, mark.postalCode].compactMap { $0 }
                    .filter { !$0.isEmpty }.joined(separator: " ")
            }
        }
    }

    @Published private(set) var suggestions: [Answer] = []
    private let completer = MKLocalSearchCompleter()

    /// What he has typed, and the outright search waiting on it. See `search`.
    private var asked = ""
    private var searching: Task<Void, Never>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func look(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        asked = trimmed
        searching?.cancel()
        guard trimmed.count >= 3 else {
            suggestions = []
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        searching?.cancel()
        asked = ""
        suggestions = []
        completer.queryFragment = ""
    }

    /// A suggestion carries only text, so the coordinate has to be asked for.
    func resolve(_ answer: Answer)
        async -> (address: String, coordinate: CLLocationCoordinate2D)? {
        switch answer {
        case .found(let item):
            return (Self.write(item), item.placemark.coordinate)
        case .suggested(let completion):
            let request = MKLocalSearch.Request(completion: completion)
            guard let response = try? await MKLocalSearch(request: request).start(),
                  let item = response.mapItems.first else { return nil }
            return (Self.write(item), item.placemark.coordinate)
        }
    }

    /// **Autocomplete does not know every house on a street it knows.**
    /// `2514 Cayman Rd, Malibu` — a real location he was scouting — returns
    /// nothing from the completer, which has `Cayman Road, Malibu` and has
    /// `2514 Cayman Rd` in five other towns, but not the two together. Search
    /// the words outright and it comes back first time, which is what the Maps
    /// app does when its own suggestions run dry. Remote addresses are exactly
    /// the ones a scout has, so an empty list here is not an answer.
    private func search() {
        searching?.cancel()
        let text = asked
        guard text.count >= 3 else { return }
        searching = Task { [weak self] in
            // Let him finish the word before spending a search on it.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            let response = try? await MKLocalSearch(request: request).start()
            guard !Task.isCancelled, let self, self.asked == text else { return }
            self.suggestions = (response?.mapItems ?? []).prefix(8).map { .found($0) }
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = completer.results
        Task { @MainActor in
            if found.isEmpty {
                self.search()
            } else {
                self.searching?.cancel()
                self.suggestions = found.map { .suggested($0) }
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter,
                               didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
            self.search()
        }
    }

    /// An address written the way a call sheet writes one.
    ///
    /// A place with a name keeps it on the first line. Somewhere like Balboa
    /// Park has no street number at all, and reducing it to "San Diego CA"
    /// throws away the only part that says which place it is.
    static func write(_ item: MKMapItem) -> String {
        let street = write(item.placemark) ?? ""
        guard let name = item.name, !name.isEmpty else { return street }
        // Don't say it twice: a street address's name *is* the street.
        if street.hasPrefix(name) || name.hasPrefix(street.components(separatedBy: "\n").first ?? "") {
            return street.isEmpty ? name : street
        }
        return street.isEmpty ? name : name + "\n" + street
    }

    static func write(_ placemark: CLPlacemark) -> String? {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let town = [placemark.locality, placemark.administrativeArea]
            .compactMap { $0 }
            .joined(separator: " ")
        let lines = [street, [town, placemark.postalCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")]
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// What address a coordinate is at — so "Current Location" fills the field
    /// in rather than leaving him to type where he is already standing.
    static func address(at coordinate: CLLocationCoordinate2D) async -> String? {
        let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(point).first else {
            return nil
        }
        return write(placemark)
    }
}
