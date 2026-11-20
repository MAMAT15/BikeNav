
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

- Bike name
- Bike type (city, folding, cargo, hybrid, road, etc.)
- Electric bike status
- E-bike class selection

Bike profiles are currently stored locally on the device using SharedPreferences.

### Live map navigation

The app supports:

- Current location detection
- Place search and destination lookup
- Route planning between two points
- Turn-by-turn style route guidance
- Route recalculation while navigation is active
- The ability to avoid ferries when needed
- Optional NYC Subway routing

The MTA schedule download is about 20 MB on first use and refreshes hourly. It is not a real-time feed, and published schedules may not include every service change.

### Community path tracking

Riders can record routes and submit them as community paths. Each path includes:

- Start and end labels
- Recorded GPS points
- Distance and duration
- Optional description
- Bike type metadata
- Confirmation counts from other users

Community paths are currently stored locally. The app includes a confirmation and verification workflow, and verified paths can be considered during route planning.

### Route optimization

BikeNav can compare a standard bike route against available verified community paths and prefer a path-based option when it provides a better route.

## Tech Stack

- Flutter
- Dart
- Flutter Map for map display
- Geolocator for location and GPS tracking
- OpenStreetMap-based map tiles
- Photon for place search
- Valhalla for bicycle routing
- SharedPreferences for local data storage
- Supabase Auth for user authentication

## Project Structure

```text
lib/
  auth_gateway.dart          # Handles Supabase sign-in and sign-up
  config.dart                # Supabase project configuration
  main.dart                  # App entry point, map, and main navigation
  screens/
    add_path.dart            # Records and submits community paths
    community_paths.dart     # Displays and confirms community paths
    route_preferences.dart   # Bike and route preference settings
  services/
    mta_subway_service.dart  # Loads and processes MTA schedule data
    path_service.dart        # Handles local community path storage

test/
  community_paths_test.dart          # Tests community path features
  fake_auth_gateway.dart             # Fake authentication service for testing
  mta_subway_service_test.dart        # Tests MTA schedule functionality
  route_preferences_test.dart        # Tests route preference settings
  train_station_selection_test.dart  # Tests train station selection
  widget_test.dart                   # Flutter widget tests

supabase/
  migrations/                # Database migration files
```

## Prerequisites

Before running BikeNav, make sure your development environment is properly set up. Follow the installation steps for your operating system.

### 1. Install Git

Git is used to download the BikeNav project from GitHub.

1. Open https://git-scm.com/downloads.
2. Select your operating system.
3. Download and run the installer.
4. Follow the installation wizard. The default installation options are suitable for most users.
5. After installation, open PowerShell, Command Prompt, or a terminal and run:

```bash
git --version
```

If Git is installed correctly, the terminal will display its installed version.

### 2. Install Flutter SDK

Flutter is the framework used to build and run BikeNav. The Dart SDK is included with Flutter, so you do not need to install Dart separately.

1. Open the official Flutter installation page: https://docs.flutter.dev/install.
2. Select your operating system (Windows, macOS, or Linux).
3. Follow the instructions to download the Flutter SDK.
4. Use the latest stable Flutter release that satisfies the project's SDK requirements in `pubspec.yaml`.
5. Extract the SDK into a folder that is easy to find.

**For Windows users:**

A recommended location is:

```text
C:\src\flutter
```

Avoid extracting Flutter into a folder that requires administrator permission or has spaces in its path.

**Add Flutter to the PATH environment variable:**

This allows you to run Flutter commands from any terminal.

1. Open the Windows Start menu.
2. Search for `Environment Variables`.
3. Select **Edit the system environment variables**.
4. Click **Environment Variables**.
5. Under **User variables**, select `Path` and click **Edit**.
6. Click **New** and enter the Flutter `bin` folder path. For example:

```text
C:\src\flutter\bin
```

7. Click **OK** to save the changes.
8. Close and reopen PowerShell or Command Prompt.

**For macOS and Linux users:**

Follow the official instructions for adding Flutter to PATH:

https://docs.flutter.dev/install/add-to-path

**Verify the Flutter and Dart installation:**

Open a new terminal and run:

```bash
flutter --version
```

Then check Dart:

```bash
dart --version
```

Both commands should display their installed versions.

### 3. Install Android Studio and Android SDK

Android Studio provides the tools needed to build and test BikeNav on Android.

1. Download Android Studio from https://developer.android.com/studio.
2. Run the installer and follow the setup wizard.
3. Open Android Studio after installation.
4. Complete the initial setup and allow it to download the recommended Android SDK components.
5. Open **More Actions → SDK Manager** from the welcome screen. If a project is already open, select **Tools → SDK Manager**.
6. Under **SDK Platforms**, install a suitable Android SDK platform.
7. Open the **SDK Tools** tab and make sure the following components are installed:
   - Android SDK Build-Tools
   - Android SDK Platform-Tools
   - Android SDK Command-line Tools
   - Android Emulator
8. Click **Apply** and wait for the installation to finish.

**Install the Flutter plugin in Android Studio:**

1. Open Android Studio.
2. Go to **File → Settings → Plugins** on Windows, or **Android Studio → Settings → Plugins** on macOS.
3. Select the **Marketplace** tab.
4. Search for `Flutter`.
5. Click **Install**.
6. Accept the prompt to install the Dart plugin if requested.
7. Restart Android Studio.

Note: Installing the Flutter plugin does not replace the Flutter SDK. You must install the Flutter SDK and configure its PATH separately.

### 4. Install Visual Studio Code (Optional)

Visual Studio Code can be used as a code editor instead of Android Studio.

1. Download VS Code from https://code.visualstudio.com/.
2. Install and open VS Code.
3. Open the Extensions panel.
4. Search for and install the **Flutter** extension.
5. The Dart extension will also be installed as a dependency.

Android Studio is still needed for the Android SDK and Emulator unless those tools have been installed separately.

### 5. Verify the Development Environment

After installing Flutter, Git, and Android Studio, open a new terminal and run:

```bash
flutter doctor
```

Flutter Doctor checks whether Flutter, Android Studio, and the required development tools are installed correctly.

If Android licenses need to be accepted, run:

```bash
flutter doctor --android-licenses
```

Read and accept the license agreements when prompted.

Run `flutter doctor` again to check the results. Resolve any issues related to the platforms you plan to use before running BikeNav.

For additional help, see the official Flutter Android setup guide:

https://docs.flutter.dev/platform-integration/android/setup

### 6. iOS Development Requirements

To run BikeNav on iOS, you need:

- A Mac computer
- Xcode installed from the Mac App Store
- Xcode command-line tools
- An iOS Simulator or a connected iPhone

After installing Xcode, open it once and complete its initial setup.

**Note:** Xcode and the iOS Simulator are not available on Windows.

### 7. Internet and Permissions

BikeNav requires an internet connection for:

- Map tiles
- Place search
- Bicycle route requests
- Supabase authentication
- MTA schedule downloads

Location permission must be enabled for GPS-based navigation and route recording.

The Supabase project configuration must also be available in `lib/config.dart`.

## Running the App

### 1. Clone the Repository

Open a terminal (PowerShell, Command Prompt, or the VS Code terminal) and run:

```bash
git clone https://github.com/MAMAT15/BikeNav.git
```

Enter the project directory:

```bash
cd BikeNav
```

### 2. Check the Development Environment

Run:

```bash
flutter doctor
```

Make sure the required Flutter and Android toolchains are ready before continuing.

### 3. Install Project Dependencies

Run:

```bash
flutter pub get
```

This downloads the packages required by BikeNav.

### 4. Create an Android Emulator

If you have not created an emulator yet, follow these steps:

1. Open Android Studio.
2. On the welcome screen, select **More Actions → Virtual Device Manager**. If a project is open, select **Tools → Device Manager**.
3. Click **Create Virtual Device**.
4. Select a phone model, such as Pixel, and click **Next**.
5. Choose an available Android system image.
6. If the system image is not installed, click its download button and wait for the download to finish.
7. Click **Next**, review the device settings, and click **Finish**.

Your new virtual device should now appear in Device Manager.

### 5. Start the Android Emulator

1. Open Android Studio.
2. Go to **Device Manager**.
3. Find the virtual device you created.
4. Click the **Play** button next to the device.
5. Wait for the emulator to finish starting and display the Android home screen.

Keep the emulator running while launching BikeNav.

**Troubleshooting: Emulator Stuck on a Black Screen**

If the Android Emulator stays on a black screen, gets stuck during startup, or does not boot properly:

1. Open Android Studio.
2. Go to **Device Manager**.
3. Find the virtual device that is having problems.
4. Click the three-dot menu (⋮) next to the device.
5. Select **Cold Boot Now**.
6. Wait for the emulator to restart.

Cold Boot starts the emulator without restoring its previous saved state. This can help fix startup problems.

If the emulator still does not work, you can try **Wipe Data** from the same menu. This resets the virtual device and deletes its stored data, so use it only if necessary.

### 6. Using a Physical Android Device (Optional)

You can also run BikeNav on a physical Android phone.

1. Enable Developer Options on the phone.
2. Enable USB Debugging.
3. Connect the phone to the computer using a USB cable.
4. Approve the USB debugging permission prompt on the phone.

### 7. Check Available Devices

Open a terminal in the project directory and run:

```bash
flutter devices
```

Flutter should display the running Android Emulator or connected physical device.

Example:

```text
sdk gphone64 x86 64 (mobile)
```

Use the device ID shown on your own computer when selecting a device.

### 8. Run BikeNav

To launch the app on the available device, run:

```bash
flutter run
```

To select a specific device, use:

```bash
flutter run -d <device-id>
```

Replace `<device-id>` with the ID displayed by `flutter devices`.

Wait for Flutter to finish building and installing the application. BikeNav should then open on the emulator or connected device.

### 9. Allow Location Access

When the app requests location permission:

1. Allow the app to access your location.
2. Make sure the device's location service is turned on.
3. For emulator testing, use the emulator's location controls to set a simulated location if needed.

GPS-based navigation and route recording require location access.

### Running on iOS Simulator

On a Mac with Xcode installed:

1. Open Xcode.
2. Go to **Xcode → Open Developer Tool → Simulator**.
3. Select an available iPhone simulator.
4. Open a terminal in the project directory.
5. Check available devices:

```bash
flutter devices
```

6. Run the app:

```bash
flutter run -d <ios-simulator-id>
```

Replace `<ios-simulator-id>` with the ID displayed by `flutter devices`.

## Useful Commands

Check for code issues:

```bash
flutter analyze
```

Run all project tests:

```bash
flutter test
```

Build an Android release APK:

```bash
flutter build apk
```

The generated APK is located at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Current Project Notes

- Supabase is used for account authentication.
- Bike profiles are currently stored locally using SharedPreferences.
- Community paths are currently stored locally through PathService. Server-side community path storage is not yet integrated.
- The MTA timetable uses published schedule data, not real-time train arrivals or service alerts.
- Place search uses Photon, and bicycle routes are requested from Valhalla.
- The map uses OpenStreetMap-based map tiles. Follow the tile provider's usage policy when deploying the app to more users.

## Releases

Android users can install a published APK from the repository's Releases page when a release is available.

## License

This project does not currently have a specific license.
