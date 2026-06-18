# basic_photo_viewer

A lightweight, native-feeling **macOS photo viewer** built with Flutter. Open an
image straight from Finder, view it, zoom, rotate, and flip through the rest of
the folder — without launching a heavyweight photo library.

## Features

- **Open from Finder** — set it as the default app for images, or use
  _Open With → Photo Viewer_ from the macOS context menu.
- **Drag & drop** — drop an image file anywhere onto the window to open it.
- **Zoom** — scroll the mouse wheel / trackpad to zoom in and out, or use the
  toolbar buttons. Pinch-and-pan is also supported via an interactive viewer.
- **Rotate** — rotate the image in 45° steps left or right.
- **Folder navigation** — when you open an image, the rest of the supported
  images in the same folder are loaded automatically so you can page through
  them. The folder is scanned on a background isolate, so opening stays instant.
- **Light & dark theme** — follows the system appearance automatically.
- **Reset** — return to the original zoom and rotation with one click.

### Supported formats

`.jpg` · `.jpeg` · `.png` · `.gif` · `.bmp` · `.tiff` / `.tif` · `.webp` · `.heic`

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `←` / `→` | Previous / next image in the folder |
| `Cmd` + `←` | Rotate 45° left |
| `Cmd` + `→` | Rotate 45° right |
| Mouse / trackpad scroll | Zoom in / out |

## Getting started

This is a standard Flutter app. You'll need the
[Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart `^3.8.1`) with
macOS desktop support enabled.

```bash
# Install dependencies
flutter pub get

# Run in debug mode on macOS
flutter run -d macos

# Build a release app bundle
flutter build macos
```

The release build is produced at
`build/macos/Build/Products/Release/basic_photo_viewer.app`.

## Project structure

- `lib/main.dart` — the entire app: UI, image rendering, zoom/rotate/navigation
  logic, and the platform channel that receives files from Finder.
- `macos/` — the macOS runner, including the native side of the "Open With"
  integration.
- `test/` — widget tests.

## How "Open With" works

When macOS opens a file with the app, the native runner sends the file path (and
the surrounding folder listing) to Flutter over a
[`MethodChannel`](https://docs.flutter.dev/platform-integration/platform-channels)
(`com.example.basic_photo_viewer/file`). The Dart side renders the requested
image immediately, then backfills the folder's image list for navigation.

## License

Released under the [MIT License](LICENSE).
