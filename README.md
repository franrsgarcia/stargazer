# Stargazer

Stargazer is an iOS AR app skeleton for tracking the Sun, Moon, and major planets in the sky.

## What is included

- `StargazerApp.swift`: app entry point
- `ContentView.swift`: SwiftUI sky overlay UI
- `ARViewContainer.swift`: ARKit / RealityKit view with live camera feed
- `StargazerModel.swift`: location and sky model state
- `LocationManager.swift`: location/heading updates
- `CelestialCalculator.swift`: approximate astronomical calculations
- `CelestialBody.swift`: body data model
- `Info.plist`: required camera/location permissions

## Run instructions

1. Open `Stargazer.xcodeproj` in Xcode.
2. Select a device that supports ARKit.
3. Build and run.

## Notes

- The app uses `ARWorldTrackingConfiguration` with `gravityAndHeading` to align the AR view with true north.
- The overlay is computed from the current time and user location.
- The calculator uses a low-precision orbital approximation to visualize major solar system bodies.
