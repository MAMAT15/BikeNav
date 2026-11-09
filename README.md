# BikeNav

## Run

```sh
flutter pub get
# Run on an Android device or emulator
flutter run -d <device-id>
```

Connect an Android phone with USB debugging enabled, or start an Android emulator.
Use `flutter devices` to find its device ID. Allow location access in the app to
use your current position and live navigation. The app needs internet access for
maps and route search. Use the account menu to add or update the bike profile;
each profile is saved with its account.

## Build Android APK

```sh
flutter build apk
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.