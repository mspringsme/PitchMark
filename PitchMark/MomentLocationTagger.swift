//
//  MomentLocationTagger.swift
//  PitchMark
//
//  2026-10-08 - resolves the current city name for a Moment that opts in
//  to location tagging (MomentsLibraryView's "Tag Location" checkbox).
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import CoreLocation

/// Every failure path (permission denied, no fix, geocoding failure,
/// timeout) resolves `nil` rather than throwing - tagging a Moment with
/// its city is a nice-to-have, never something that should block or
/// error out a save.
final class MomentLocationTagger: NSObject, CLLocationManagerDelegate {
    static let shared = MomentLocationTagger()

    private let manager = CLLocationManager()
    private var completion: ((String?) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
        manager.delegate = self
    }

    func fetchCityName(completion: @escaping (String?) -> Void) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            self.completion = completion
            armTimeout()
            manager.requestLocation()
        case .notDetermined:
            self.completion = completion
            armTimeout()
            manager.requestWhenInUseAuthorization()
        default:
            completion(nil)
        }
    }

    private func armTimeout() {
        timeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finish(with: nil)
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: workItem)
    }

    private func finish(with city: String?) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        let callback = completion
        completion = nil
        callback?(city)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(with: nil)
            return
        }
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            self?.finish(with: placemarks?.first?.locality)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }
}
