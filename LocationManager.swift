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
        manager.headingFilter = 5
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        if CLLocationManager.locationServicesEnabled() {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
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
