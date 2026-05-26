import Foundation
import CoreLocation

protocol LocationManagerDelegate: AnyObject {
    func locationManager(didUpdate location: CLLocation?, heading: CLHeading?)
}

final class LocationManager: NSObject {
    private let manager = CLLocationManager()
    weak var delegate: LocationManagerDelegate?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 1
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        startUpdatesIfAuthorized()
    }

    private func startUpdatesIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            manager.headingOrientation = .portrait
            manager.startUpdatingHeading()
        default:
            break
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startUpdatesIfAuthorized()
        delegate?.locationManager(didUpdate: manager.location, heading: manager.heading)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        delegate?.locationManager(didUpdate: locations.last, heading: manager.heading)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        delegate?.locationManager(didUpdate: manager.location, heading: newHeading)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        delegate?.locationManager(didUpdate: manager.location, heading: manager.heading)
    }
}
