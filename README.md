# My Medical History — Flutter Android SQLite Demo

This is a classroom prototype. Use **fictional** information only; SQLite is not encrypted by default.

## Files
- `lib/main.dart`: Flutter UI + doctor-wise visits + SQLite CRUD
- `pubspec.yaml`: sqflite and path packages
- `codemagic.yaml`: generates Android scaffold and builds debug APK online

## Online build (no Android Studio)
1. Create an empty GitHub repository.
2. Upload the project files/folders, maintaining paths.
3. Open https://codemagic.io and connect the repository as a Flutter app.
4. Select the `android-debug` workflow from `codemagic.yaml` and start a build.
5. Download `app-debug.apk` from the build artifacts when successful.
6. Install the APK on Android (grant installation permission only for a trusted source).

## Testing
1. Add two visits for the same doctor and a third for another doctor.
2. Visit Doctors tab and open a doctor profile.
3. Edit and delete a visit; confirm the doctor count updates.
4. Force close and relaunch the Android app; visits should remain.
5. Reboot phone and relaunch; visits should remain.

## Limitations
- No cloud backup or Google Drive sync.
- No photos, documents, geolocation, authentication or encryption.
- SQLite data is private app data but is deleted if app data is cleared or app uninstalled.
- Doctor grouping is by normalized name; unique doctor IDs should be added in a production app.
- Requires current Android SDK and a compatible Codemagic Flutter environment.
