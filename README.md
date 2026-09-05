# DoctorDesk Mobile App

DoctorDesk is a Flutter-based mobile healthcare application that allows patients to find doctors, explore specialties, discover nearby medical chambers, read health feeds, book appointments, and maintain daily health journals.

---

## 📋 Prerequisites

Before running the application, ensure you have:

1. **[Flutter SDK](https://docs.flutter.dev/get-started/install)** (Version `>= 3.0.0 < 4.0.0`)
   - Verify your installation by running:
     ```bash
     flutter doctor
     ```
2. **Device / Emulator**:
   - An Android emulator, physical Android device (with USB debugging enabled), iOS simulator, macOS, or Google Chrome.
3. **DoctorDesk Backend Running**:
   - Ensure the Node.js backend server (`doctordesk-backend`) is up and running (default: port `5000`).

---

## ⚙️ Backend API Configuration (`API_BASE_URL`)

The app communicates with the DoctorDesk backend. The API base URL can be passed dynamically at runtime using `--dart-define=API_BASE_URL=...` or configured in code.

Choose the URL that matches your target runtime:

| Target Platform | `API_BASE_URL` Value | Explanation |
| :--- | :--- | :--- |
| **Android Emulator** | `http://10.0.2.2:5000/api/v1` | `10.0.2.2` routes to host machine's `localhost` |
| **Physical Phone (Wi-Fi)** | `http://<YOUR_PC_IP>:5000/api/v1` | e.g., `http://192.168.1.100:5000/api/v1` (Phone & PC must be on same Wi-Fi) |
| **iOS Simulator** | `http://localhost:5000/api/v1` | Shares host network directly |
| **Web (Chrome)** | `http://localhost:5000/api/v1` | Runs directly in your browser |
| **Windows Desktop** | `http://localhost:5000/api/v1` | Localhost loopback |

> 💡 **Tip**: You can also permanently change the default fallback value in [`lib/services/api_service.dart`](lib/services/api_service.dart):
> ```dart
> static const String baseUrl = String.fromEnvironment(
>   'API_BASE_URL',
>   defaultValue: 'http://10.0.2.2:5000/api/v1', // change this to your preferred URL
> );
> ```

---

## 🚀 Installation & Running

1. **Navigate to the Flutter directory:**
   ```bash
   cd doctordesk-flutter
   ```

2. **Fetch Flutter dependencies:**
   ```bash
   flutter pub get
   ```

3. **Check available devices:**
   ```bash
   flutter devices
   ```

4. **Run the App:**

   - **For Android Emulator:**
     ```bash
     flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000/api/v1
     ```

   - **For Physical Mobile Device (Replace with your computer's local Wi-Fi IP):**
     ```bash
     flutter run --dart-define=API_BASE_URL=http://192.168.1.100:5000/api/v1
     ```

   - **For iOS Simulator / Desktop / Local:**
     ```bash
     flutter run --dart-define=API_BASE_URL=http://localhost:5000/api/v1
     ```

   - **For Web (Chrome):**
     ```bash
     flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5000/api/v1
     ```

---

## 💻 VS Code Debug Configuration (Optional)

If you use VS Code, you can add this configuration to `.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "DoctorDesk (Android Emulator)",
      "request": "launch",
      "type": "dart",
      "args": [
        "--dart-define=API_BASE_URL=http://10.0.2.2:5000/api/v1"
      ]
    },
    {
      "name": "DoctorDesk (Localhost / iOS)",
      "request": "launch",
      "type": "dart",
      "args": [
        "--dart-define=API_BASE_URL=http://localhost:5000/api/v1"
      ]
    }
  ]
}
```

---

## 📦 Building for Release (Android APK)

To build a standalone APK for testing or distribution:

```bash
flutter build apk --release --dart-define=API_BASE_URL=http://<YOUR_SERVER_IP>:5000/api/v1
```

The output APK will be generated at:
`build/app/outputs/flutter-apk/app-release.apk`

---

## 🛠️ Common Troubleshooting

- **`SocketException: Connection refused` / App cannot load doctors:**
  - Verify that `doctordesk-backend` is running (`npm start`) on port `5000`.
  - Check that the `API_BASE_URL` you supplied matches your platform (e.g. use `10.0.2.2` for Android Emulator, NOT `localhost`).
  - If using a physical phone, ensure your computer and phone are connected to the same Wi-Fi network and your firewall permits incoming traffic on port 5000.
- **Location Permission Prompt:**
  - The "Nearby Doctors" screen requires device location access. Grant location permission when prompted by the app.
