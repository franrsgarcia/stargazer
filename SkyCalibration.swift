import Foundation
import simd
import ARKit

enum SkyCalibration {
    private static let azimuthKey = "stargazer.azimuthOffset"
    private static let altitudeKey = "stargazer.altitudeOffset"
    private static let calibratedKey = "stargazer.isCalibrated"

    static func load() -> (azimuth: Double, altitude: Double, isCalibrated: Bool) {
        (
            UserDefaults.standard.double(forKey: azimuthKey),
            UserDefaults.standard.double(forKey: altitudeKey),
            UserDefaults.standard.bool(forKey: calibratedKey)
        )
    }

    static func save(azimuthOffset: Double, altitudeOffset: Double) {
        UserDefaults.standard.set(azimuthOffset, forKey: azimuthKey)
        UserDefaults.standard.set(altitudeOffset, forKey: altitudeKey)
        UserDefaults.standard.set(true, forKey: calibratedKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: azimuthKey)
        UserDefaults.standard.removeObject(forKey: altitudeKey)
        UserDefaults.standard.set(false, forKey: calibratedKey)
    }

    static func normalizeDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value
    }

    static func shortestSignedDelta(from: Double, to: Double) -> Double {
        var delta = normalizeDegrees(to - from)
        if delta > 180 { delta -= 360 }
        return delta
    }

    /// Horizontal compass azimuth (0° = north, 90° = east) of the camera forward vector.
    static func cameraAzimuthDegrees(from transform: simd_float4x4) -> Double {
        let forward = SIMD3<Float>(
            -transform.columns.2.x,
            -transform.columns.2.y,
            -transform.columns.2.z
        )
        let horizontal = sqrt(forward.x * forward.x + forward.z * forward.z)
        guard horizontal > 0.0001 else { return 0 }
        let radians = atan2(Double(forward.x), Double(-forward.z))
        return normalizeDegrees(radians * 180 / .pi)
    }

    /// Elevation of the camera forward vector in degrees.
    static func cameraAltitudeDegrees(from transform: simd_float4x4) -> Double {
        let forward = SIMD3<Float>(
            -transform.columns.2.x,
            -transform.columns.2.y,
            -transform.columns.2.z
        )
        let length = simd_length(forward)
        guard length > 0.0001 else { return 0 }
        return asin(Double(forward.y / length)) * 180 / .pi
    }

    static func northCalibrationOffset(deviceAzimuth: Double, trueNorth: Double) -> Double {
        shortestSignedDelta(from: deviceAzimuth, to: trueNorth)
    }

    static func sunCalibrationOffset(deviceAzimuth: Double, sunAzimuth: Double) -> Double {
        shortestSignedDelta(from: deviceAzimuth, to: sunAzimuth)
    }

    static func angularSeparation(
        azimuthA: Double,
        altitudeA: Double,
        azimuthB: Double,
        altitudeB: Double
    ) -> Double {
        let az1 = azimuthA * .pi / 180
        let az2 = azimuthB * .pi / 180
        let alt1 = altitudeA * .pi / 180
        let alt2 = altitudeB * .pi / 180

        let ax = cos(alt1) * sin(az1)
        let ay = sin(alt1)
        let az = -cos(alt1) * cos(az1)

        let bx = cos(alt2) * sin(az2)
        let by = sin(alt2)
        let bz = -cos(alt2) * cos(az2)

        let dot = max(-1, min(1, Double(ax * bx + ay * by + az * bz)))
        return acos(dot) * 180 / .pi
    }
}
