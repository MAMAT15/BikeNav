# BikeNav

BikeNav is a Flutter mobile app for planning, saving, and sharing bike-friendly routes. It helps riders navigate using live location, find bike routes based on their current position, and build a community-backed network of verified paths.

## Overview

BikeNav combines standard navigation with a cyclist-specific routing experience:

- Personalized rider accounts and saved bike profiles
- Live GPS location support for navigation and ride recording
- Route planning from origin to destination with bicycle-friendly options
- Community path submissions, confirmations, and verification
- Route suggestions that can use verified rider paths when they improve the trip

The app is designed for urban and recreational cycling, with a focus on practical navigation and community-generated route quality.

## Features

### Rider accounts and bike profiles

Users can create an account, log in, and save a bike profile with:

- bike name
- bike type (city, folding, cargo, hybrid, road, etc.)
- electric bike status
- e-bike class selection

Profiles are stored locally on the device so each signed-in user keeps their personal bike settings.

### Live map navigation

The app supports:

- current location detection
- place search and destination lookup
- route planning between two points
- turn-by-turn style route guidance
- route recalculation while navigation is active
- the ability to avoid ferries when needed
- optional NYC Subway routing

The MTA schedule download is about 20 MB on first use and refreshes hourly. It is not a real-time feed, and published schedules may not include every service change.

### Community path tracking

Riders can record routes and submit them as community paths. Each path includes:

- start and end labels
- recorded GPS points
- distance and duration
- optional description
- bike type metadata
- confirmation counts from other users

A path is only considered verified after enough riders confirm it, and verified community paths can be used as route shortcuts when they improve the trip.

### Route optimization

BikeNav can compare a standard bike route against verified community paths and prefer the path-based option when it produces a faster route. This creates a lightweight community-driven routing layer without requiring a backend database.

## Tech stack

- Flutter
- Dart
- Google Maps-style map UI via Flutter Map
- Geolocation via Geolocator
- OpenStreetMap-based search and route APIs
- Local persistence using SharedPreferences


## Prerequisites

Before running the app, make sure you have:

- Flutter SDK installed
- An Android emulator running, or a physical Android device connected via USB debugging
- Location services enabled on your device
- Internet access for map and route search requests

## Running the app

### Installation & Local Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/MAMAT15/BikeNav.git
   cd BikeNav
   ```

2. Install the project dependencies:
   ```bash
   flutter pub get
   ```

3. Verify your Flutter environment:
   ```bash
   flutter doctor
   ```
   Make sure Flutter, Android toolchain, and device/emulator support are configured correctly.

4. Start an Android emulator or connect a physical device:
   ```bash
   flutter devices
   ```
   Then select a target device or emulator.

5. Run the app locally:
   ```bash
   flutter run
   ```
   If you want to target a specific device:
   ```bash
   flutter run -d <device-id>
   ```

6. Allow location permissions when prompted:
   BikeNav requires access to GPS/location services for route planning and live navigation.

## Building an Android APK

```bash
flutter build apk
```

The APK is generated at:

```text
build/app/outputs/flutter-apk/app-release.apk
```
## For Users Usage

Go to Releases and download the latest version on your android phone as an APK file. Keep an eye out for new releases as it will include more features and optimizations.

## License

This project does not currently have a specific license.
