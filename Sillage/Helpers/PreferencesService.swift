//
//  PreferencesService.swift
//  Sillage
//

import Foundation
import CoreLocation

protocol PreferencesServiceProtocol {
    var savedMapSource: String? { get set }
    var savedLatitude: Double? { get set }
    var savedLongitude: Double? { get set }
    var savedZoom: Double? { get set }

    func saveCameraState(coordinate: CLLocationCoordinate2D, zoom: Double)
    func loadCameraState() -> (coordinate: CLLocationCoordinate2D, zoom: Double)?
}

class PreferencesService: PreferencesServiceProtocol {
    static let shared = PreferencesService()

    private let mapSourceKey = "selectedMapSource"
    private let savedLatitudeKey = "savedLatitude"
    private let savedLongitudeKey = "savedLongitude"
    private let savedZoomKey = "savedZoom"

    private let defaults = UserDefaults.standard

    var savedMapSource: String? {
        get { defaults.string(forKey: mapSourceKey) }
        set { defaults.set(newValue, forKey: mapSourceKey) }
    }

    var savedLatitude: Double? {
        get { defaults.object(forKey: savedLatitudeKey) as? Double }
        set { defaults.set(newValue, forKey: savedLatitudeKey) }
    }

    var savedLongitude: Double? {
        get { defaults.object(forKey: savedLongitudeKey) as? Double }
        set { defaults.set(newValue, forKey: savedLongitudeKey) }
    }

    var savedZoom: Double? {
        get { defaults.object(forKey: savedZoomKey) as? Double }
        set { defaults.set(newValue, forKey: savedZoomKey) }
    }

    func saveCameraState(coordinate: CLLocationCoordinate2D, zoom: Double) {
        savedLatitude = coordinate.latitude
        savedLongitude = coordinate.longitude
        savedZoom = zoom
    }

    func loadCameraState() -> (coordinate: CLLocationCoordinate2D, zoom: Double)? {
        if let lat = savedLatitude, let lon = savedLongitude, let zoom = savedZoom {
            return (CLLocationCoordinate2D(latitude: lat, longitude: lon), zoom)
        }
        return nil
    }
}
