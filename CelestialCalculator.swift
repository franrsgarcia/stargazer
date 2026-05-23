import Foundation
import CoreLocation
import SwiftUI

struct CelestialCalculator {
    static func bodies(at date: Date, location: CLLocationCoordinate2D) -> [CelestialBody] {
        let sun = sunBody(at: date, location: location)
        let moon = moonBody(at: date, location: location)
        let planets = planetBodies(at: date, location: location)
        return [sun, moon] + planets
    }

    static func directionVector(
        azimuth: Double,
        altitude: Double,
        azimuthOffset: Double = 0,
        altitudeOffset: Double = 0
    ) -> SIMD3<Float> {
        let az = degreesToRadians(normalizeAngle(azimuth + azimuthOffset))
        let alt = degreesToRadians(altitude + altitudeOffset)
        let x = Float(cos(alt) * sin(az))
        let y = Float(sin(alt))
        let z = Float(-cos(alt) * cos(az))
        return SIMD3<Float>(x, y, z)
    }

    static func sunBody(at date: Date, location: CLLocationCoordinate2D) -> CelestialBody {
        let sunCoords = equatorialCoordinatesForSun(date: date)
        let horizontal = horizontalCoordinates(ra: sunCoords.ra, dec: sunCoords.dec, date: date, location: location)
        return CelestialBody(
            name: "Sun",
            type: .sun,
            azimuth: horizontal.azimuth,
            altitude: horizontal.altitude,
            distanceAu: sunCoords.distanceAu,
            color: .yellow
        )
    }

    static func moonBody(at date: Date, location: CLLocationCoordinate2D) -> CelestialBody {
        let moonCoords = equatorialCoordinatesForMoon(date: date)
        let horizontal = horizontalCoordinates(ra: moonCoords.ra, dec: moonCoords.dec, date: date, location: location)
        return CelestialBody(
            name: "Moon",
            type: .moon,
            azimuth: horizontal.azimuth,
            altitude: horizontal.altitude,
            distanceAu: moonCoords.distanceAu,
            color: .white
        )
    }

    static func planetBodies(at date: Date, location: CLLocationCoordinate2D) -> [CelestialBody] {
        let planetElements = Planet.orbitElements
        let earthPosition = heliocentricPosition(of: .earth, at: date)
        return planetElements.compactMap { planet in
            guard planet != .earth else { return nil }
            let planetPosition = heliocentricPosition(of: planet, at: date)
            let geo = geocentricCoordinates(for: planetPosition, earthPosition: earthPosition)
            let eq = equatorialCoordinates(eclipticLongitude: geo.longitude, eclipticLatitude: geo.latitude)
            let horizontal = horizontalCoordinates(ra: eq.ra, dec: eq.dec, date: date, location: location)
            return CelestialBody(
                name: planet.rawValue,
                type: .planet,
                azimuth: horizontal.azimuth,
                altitude: horizontal.altitude,
                distanceAu: geo.distanceAu,
                color: planet.color
            )
        }
    }

    private static func equatorialCoordinatesForSun(date: Date) -> (ra: Double, dec: Double, distanceAu: Double) {
        let jd = julianDay(for: date)
        let t = (jd - 2451545.0) / 36525.0
        let l0 = normalizeAngle(280.46646 + 36000.76983 * t + 0.0003032 * t * t)
        let m = normalizeAngle(357.52911 + 35999.05029 * t - 0.0001537 * t * t)
        let c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sinDegrees(m)
            + (0.019993 - 0.000101 * t) * sinDegrees(2 * m)
            + 0.000289 * sinDegrees(3 * m)
        let sunLongitude = l0 + c
        let distanceAu = 1.000001018 * (1 - pow(0.016708634 - 0.000042037 * t - 0.0000001267 * t * t, 2))
        let epsilon = 23.439291 - 0.0130042 * t
        let ra = atan2Degrees(cosDegrees(epsilon) * sinDegrees(sunLongitude), cosDegrees(sunLongitude))
        let dec = asinDegrees(sinDegrees(epsilon) * sinDegrees(sunLongitude))
        return (ra: normalizeAngle(ra), dec: dec, distanceAu: distanceAu)
    }

    private static func equatorialCoordinatesForMoon(date: Date) -> (ra: Double, dec: Double, distanceAu: Double) {
        let jd = julianDay(for: date)
        let t = (jd - 2451545.0) / 36525.0
        let lPrime = normalizeAngle(218.3164477 + 481267.88123421 * t - 0.0015786 * t * t + t * t * t / 538841 - t * t * t * t / 65194000)
        let m = normalizeAngle(357.5291092 + 35999.0502909 * t - 0.0001536 * t * t + t * t * t / 24490000)
        let mPrime = normalizeAngle(134.9633964 + 477198.8675055 * t + 0.0087414 * t * t + t * t * t / 69699 - t * t * t * t / 14712000)
        let f = normalizeAngle(93.2720950 + 483202.0175233 * t - 0.0036539 * t * t - t * t * t / 3526000 + t * t * t * t / 863310000)
        let d = normalizeAngle(297.8501921 + 445267.1114034 * t - 0.0018819 * t * t + t * t * t / 545868 - t * t * t * t / 113065000)

        let longitude = lPrime
            + 6.289 * sinDegrees(mPrime)
            + 1.274 * sinDegrees(2 * d - mPrime)
            + 0.658 * sinDegrees(2 * d)
            + 0.214 * sinDegrees(2 * mPrime)
            - 0.186 * sinDegrees(m)
            - 0.114 * sinDegrees(2 * f)

        let latitude = 5.128 * sinDegrees(f)
            + 0.280 * sinDegrees(mPrime + f)
            + 0.277 * sinDegrees(mPrime - f)
            + 0.173 * sinDegrees(2 * d - f)

        let distanceKm = 385000.56 - 20905.355 * cosDegrees(mPrime)
        let distanceAu = distanceKm / 149597870.7
        let epsilon = 23.439291 - 0.0130042 * t
        let eq = equatorialCoordinates(eclipticLongitude: longitude, eclipticLatitude: latitude)
        return (ra: eq.ra, dec: eq.dec, distanceAu: distanceAu)
    }

    private static func equatorialCoordinates(eclipticLongitude: Double, eclipticLatitude: Double) -> (ra: Double, dec: Double) {
        let lambda = degreesToRadians(eclipticLongitude)
        let beta = degreesToRadians(eclipticLatitude)
        let epsilon = degreesToRadians(23.439291)

        let x = cos(lambda) * cos(beta)
        let y = sin(lambda) * cos(beta)
        let z = sin(beta)

        let xEq = x
        let yEq = cos(epsilon) * y - sin(epsilon) * z
        let zEq = sin(epsilon) * y + cos(epsilon) * z

        let ra = normalizeAngle(radiansToDegrees(atan2(yEq, xEq)))
        let dec = radiansToDegrees(asin(zEq))
        return (ra: ra, dec: dec)
    }

    private static func horizontalCoordinates(ra: Double, dec: Double, date: Date, location: CLLocationCoordinate2D) -> (azimuth: Double, altitude: Double) {
        let lat = degreesToRadians(location.latitude)
        let lst = localSiderealTime(for: date, longitude: location.longitude)
        let hourAngle = normalizeAngle(lst - ra)

        let h = degreesToRadians(hourAngle)
        let decRad = degreesToRadians(dec)

        let altitude = radiansToDegrees(asin(sin(lat) * sin(decRad) + cos(lat) * cos(decRad) * cos(h)))
        let azimuth = radiansToDegrees(atan2(sin(h), cos(h) * sin(lat) - tan(decRad) * cos(lat)))
        return (azimuth: normalizeAngle(azimuth + 180.0), altitude: altitude)
    }

    private static func heliocentricPosition(of planet: Planet, at date: Date) -> (x: Double, y: Double, z: Double) {
        let jd = julianDay(for: date)
        let t = (jd - 2451545.0) / 36525.0
        let elems = planet.elements
        let a = elems.a
        let e = elems.e
        let i = degreesToRadians(elems.i)
        let l = normalizeAngle(elems.l + elems.lDot * t)
        let wBar = normalizeAngle(elems.wBar + elems.wBarDot * t)
        let omega = normalizeAngle(elems.omega + elems.omegaDot * t)
        let m = normalizeAngle(l - wBar)

        let eAnomaly = eccentricAnomaly(meanAnomaly: m, eccentricity: e)
        let xOrb = a * (cosDegrees(eAnomaly) - e)
        let yOrb = a * sqrt(1 - e * e) * sinDegrees(eAnomaly)
        let v = radiansToDegrees(atan2(yOrb, xOrb))
        let r = sqrt(xOrb * xOrb + yOrb * yOrb)
        let trueLongitude = v + wBar

        let x = r * (cosDegrees(omega) * cosDegrees(trueLongitude - omega) - sinDegrees(omega) * sinDegrees(trueLongitude - omega) * cos(i))
        let y = r * (sinDegrees(omega) * cosDegrees(trueLongitude - omega) + cosDegrees(omega) * sinDegrees(trueLongitude - omega) * cos(i))
        let z = r * sinDegrees(trueLongitude - omega) * sin(i)
        return (x: x, y: y, z: z)
    }

    private static func geocentricCoordinates(for planet: (x: Double, y: Double, z: Double), earthPosition: (x: Double, y: Double, z: Double)) -> (longitude: Double, latitude: Double, distanceAu: Double) {
        let x = planet.x - earthPosition.x
        let y = planet.y - earthPosition.y
        let z = planet.z - earthPosition.z
        let distance = sqrt(x * x + y * y + z * z)
        let longitude = radiansToDegrees(atan2(y, x))
        let latitude = radiansToDegrees(atan2(z, sqrt(x * x + y * y)))
        return (longitude: normalizeAngle(longitude), latitude: latitude, distanceAu: distance)
    }

    private static func localSiderealTime(for date: Date, longitude: Double) -> Double {
        let jd = julianDay(for: date)
        let t = (jd - 2451545.0) / 36525.0
        let gmst = normalizeAngle(280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t - t * t * t / 38710000.0)
        return normalizeAngle(gmst + longitude)
    }

    private static func julianDay(for date: Date) -> Double {
        return 2440587.5 + date.timeIntervalSince1970 / 86400.0
    }

    private static func eccentricAnomaly(meanAnomaly m: Double, eccentricity e: Double) -> Double {
        var e0 = m + radiansToDegrees(e) * sinDegrees(m) * (1.0 + e * cosDegrees(m))
        for _ in 0..<8 {
            let delta = (e0 - radiansToDegrees(e) * sinDegrees(e0) - m) / (1.0 - e * cosDegrees(e0))
            e0 -= delta
            if abs(delta) < 1e-6 { break }
        }
        return e0
    }

    private static func normalizeAngle(_ value: Double) -> Double {
        var angle = value
        while angle < 0 { angle += 360 }
        while angle >= 360 { angle -= 360 }
        return angle
    }

    private static func sinDegrees(_ degrees: Double) -> Double {
        sin(degreesToRadians(degrees))
    }

    private static func cosDegrees(_ degrees: Double) -> Double {
        cos(degreesToRadians(degrees))
    }

    private static func asinDegrees(_ value: Double) -> Double {
        radiansToDegrees(asin(value))
    }

    private static func acosDegrees(_ value: Double) -> Double {
        radiansToDegrees(acos(value))
    }

    private static func atan2Degrees(_ y: Double, _ x: Double) -> Double {
        radiansToDegrees(atan2(y, x))
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * Double.pi / 180.0
    }

    private static func radiansToDegrees(_ radians: Double) -> Double {
        radians * 180.0 / Double.pi
    }

    // Sample temporal trajectory positions for a named body across a time span centered on centerDate.
    static func sampleTrajectory(name: String, centerDate: Date, location: CLLocationCoordinate2D, spanMinutes: Int = 360, stepMinutes: Int = 5) -> [(date: Date, az: Double, alt: Double, isFuture: Bool)] {
        var results: [(date: Date, az: Double, alt: Double, isFuture: Bool)] = []
        let half = spanMinutes / 2
        var t = -half
        while t <= half {
            let date = centerDate.addingTimeInterval(TimeInterval(t * 60))
            let bodies = bodies(at: date, location: location)
            if let body = bodies.first(where: { $0.name == name }) {
                results.append((date: date, az: body.azimuth, alt: body.altitude, isFuture: t >= 0))
            }
            t += stepMinutes
        }
        return results
    }
}

private enum Planet: String, CaseIterable {
    case mercury = "Mercury"
    case venus = "Venus"
    case earth = "Earth"
    case mars = "Mars"
    case jupiter = "Jupiter"
    case saturn = "Saturn"

    static let orbitElements: [Planet] = [.mercury, .venus, .earth, .mars, .jupiter, .saturn]

    var color: Color {
        switch self {
        case .mercury: return .gray
        case .venus: return .orange
        case .earth: return .blue
        case .mars: return .red
        case .jupiter: return .brown
        case .saturn: return .yellow
        }
    }

    var elements: (a: Double, e: Double, i: Double, l: Double, wBar: Double, omega: Double, lDot: Double, wBarDot: Double, omegaDot: Double) {
        switch self {
        case .mercury:
            return (0.38709893, 0.20563069, 7.00487, 252.25084, 77.45645, 48.330764, 149472.67411175, 0.16047689, 0.12533786)
        case .venus:
            return (0.72333199, 0.00677323, 3.39471, 181.97973, 131.53298, 76.68069, 58517.81538729, 0.00276568, 0.27769418)
        case .earth:
            return (1.00000011, 0.01671022, 0.00005, 100.46435, 102.94719, 0.0, 35999.37244981, 0.32327364, 0.0)
        case .mars:
            return (1.52366231, 0.09341233, 1.85061, 355.45332, 336.04084, 49.57854, 19140.30268499, 0.44441088, 0.29257343)
        case .jupiter:
            return (5.20336301, 0.04839266, 1.30530, 34.40438, 14.75385, 100.55615, 3034.74612775, 0.09148219, 0.01173486)
        case .saturn:
            return (9.53707032, 0.05415060, 2.48446, 49.94432, 92.43194, 113.71504, 1222.49362201, 0.54179478, 0.01299855)
        }
    }
}
