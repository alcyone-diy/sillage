//
//  PreferencesService.swift
//  Alcyone Sillage
//

import Foundation
import CoreLocation

protocol PreferencesServiceProtocol {
    var savedMapSource: String? { get set }
    var savedLatitude: Double? { get set }
    var savedLongitude: Double? { get set }
    var savedZoom: Double? { get set }
    var savedDirection: Double? { get set }
    var gloveModeEnabled: Bool { get set }

    func saveCameraState(coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double)
    func loadCameraState() -> (coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double)?
}

class PreferencesService: PreferencesServiceProtocol {
    static let shared = PreferencesService()

    private let mapSourceKey = "selectedMapSource"
    private let savedLatitudeKey = "savedLatitude"
    private let savedLongitudeKey = "savedLongitude"
    private let savedZoomKey = "savedZoom"
    private let savedDirectionKey = "savedDirection"
    private let gloveModeEnabledKey = "gloveModeEnabled"

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

    var savedDirection: Double? {
        get { defaults.object(forKey: savedDirectionKey) as? Double }
        set { defaults.set(newValue, forKey: savedDirectionKey) }
    }

    var gloveModeEnabled: Bool {
        get { defaults.bool(forKey: gloveModeEnabledKey) }
        set { defaults.set(newValue, forKey: gloveModeEnabledKey) }
    }

    func saveCameraState(coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double) {
        savedLatitude = coordinate.latitude
        savedLongitude = coordinate.longitude
        savedZoom = zoom
        savedDirection = direction
    }

    func loadCameraState() -> (coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double)? {
        if let lat = savedLatitude, let lon = savedLongitude, let zoom = savedZoom {
            let direction = savedDirection ?? 0.0 // Default to 0 (North) if not saved
            return (CLLocationCoordinate2D(latitude: lat, longitude: lon), zoom, direction)
        }
        return nil
    }
}
