import Foundation
import CoreLocation

/// Where the phone is, asked once, when he asks for it.
///
/// Deliberately not a running subscription. A scout is a long day and a location
/// is pinned in a moment; watching continuously would cost battery all afternoon
/// to answer a question asked four times.
@MainActor
final class Whereabouts: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var isAsking = false
    @Published var refused = false

    private let manager = CLLocationManager()
    private var waiting: ((CLLocationCoordinate2D?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func pin(_ then: @escaping (CLLocationCoordinate2D?) -> Void) {
        waiting = then
        isAsking = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            refused = true
            finish(nil)
        default:
            manager.requestLocation()
        }
    }

    private func finish(_ where_: CLLocationCoordinate2D?) {
        isAsking = false
        coordinate = where_ ?? coordinate
        waiting?(where_)
        waiting = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if waiting != nil { manager.requestLocation() }
            case .denied, .restricted:
                refused = true
                finish(nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let first = locations.last?.coordinate
        Task { @MainActor in self.finish(first) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
