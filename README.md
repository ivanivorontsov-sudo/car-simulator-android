# Car Simulator Android / Автосимулятор (Android)

Android port of **Car Simulator** (Godot 4.4) — same track, vehicle physics, FPS/chase camera, damage, and auto-restart, with **on-screen touch controls**.

Порт **Автосимулятора** на Android (Godot 4.4) — та же трасса, физика, камеры FPS/преследование, повреждения и авто-рестарт, с **сенсорным управлением**.

**v1.3.4-android** · package `org.ivanivorontsov.carsimulator` · landscape · mobile renderer

![Godot](https://img.shields.io/badge/Godot-4.4.1-478cbf) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-Android-green)

## Install APK / Установка APK

The CI builds a **debug-signed APK** (sideloadable; no Play Store secrets required).

CI собирает **debug APK** (можно ставить вручную; секреты Play Store не нужны).

### English

1. Open **Actions**: [github.com/ivanivorontsov-sudo/car-simulator-android/actions](https://github.com/ivanivorontsov-sudo/car-simulator-android/actions)
2. Open workflow **Build Android APK**
3. Pick a green run (or **Run workflow**)
4. Download artifact **`car-simulator-android-apk`**
5. Unzip → install `CarSimulator-debug.apk` on the phone  
   - Enable **Install unknown apps** for your file manager/browser  
   - Android may warn that the APK is debug-signed — that is expected

### Русский

1. Откройте **Actions**: [github.com/ivanivorontsov-sudo/car-simulator-android/actions](https://github.com/ivanivorontsov-sudo/car-simulator-android/actions)
2. Workflow **Build Android APK**
3. Успешный запуск (или **Run workflow**)
4. Скачайте артефакт **`car-simulator-android-apk`**
5. Распакуйте и установите `CarSimulator-debug.apk`  
   - Разрешите установку из неизвестных источников  
   - Предупреждение о debug-подписи — нормально для этой сборки

## Touch controls / Сенсорное управление

Landscape orientation. Overlay (also works with keyboard in the Godot editor):

| Control | Action |
| --- | --- |
| **Steer pad** (left) | Drag left/right to steer; light **tilt** assist when pad is free |
| **GAS** | Throttle |
| **BRAKE** | Brake / reverse (same logic as PC) |
| **HB** | Handbrake |
| **CAM** | Chase ↔ FPS |
| **RESET** | Respawn at start |
| **❚❚** | Pause |

Keyboard (editor / Bluetooth): WASD, Shift handbrake, C camera, R reset, Esc pause — same as the PC game.

## Run from source / Из исходников

Requirements: Godot **4.4.1**, Android SDK + OpenJDK 17 for device export.

```text
1. Clone this repo
2. Godot → Import → project.godot
3. F5 (touch overlay appears on touchscreen; keyboard always works)
4. Project → Export → Android (preset included)
```

Rendering: `renderer/rendering_method="mobile"` for phones. Weak devices may need lower quality in OS settings; MSAA is reduced vs the PC build.

## Limitations / Ограничения

- **Debug APK** only (not Play Store release-signed)
- **arm64-v8a** only
- Graphics tuned for mobile — weaker phones may drop FPS; HDRI/shadows are lighter than PC Forward+
- Windows installer / PC export presets are not part of this repo (see sibling `car-simulator`)

## License / Лицензия

MIT — see [LICENSE](LICENSE). Third-party assets: [CREDITS.md](CREDITS.md).
