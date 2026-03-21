import Foundation
import CoreLocation
import Combine

protocol LocationServiceProtocol {
    var locationPublisher: PassthroughSubject<CLLocation, Never> { get }
    var authorizationStatusPublisher: PassthroughSubject<CLAuthorizationStatus, Never> { get }

    func requestAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}

class LocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {

    private let locationManager: CLLocationManager

    let locationPublisher = PassthroughSubject<CLLocation, Never>()
    let authorizationStatusPublisher = PassthroughSubject<CLAuthorizationStatus, Never>()

    override init() {
        self.locationManager = CLLocationManager()
        super.init()

        self.locationManager.delegate = self
        // Prioritize accuracy over battery for a marine environment
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        self.locationManager.distanceFilter = kCLDistanceFilterNone
    }

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatusPublisher.send(manager.authorizationStatus)

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatingLocation()
        default:
            stopUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.last else { return }

        // Filter out inaccurate GPS points (horizontal accuracy > 50m or invalid < 0)
        let accuracy = latestLocation.horizontalAccuracy
        if accuracy >= 0 && accuracy <= 50 {
            locationPublisher.send(latestLocation)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationService failed with error: \(error.localizedDescription)")
    }
}
