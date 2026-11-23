# rupaywala_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Running on the web

By default Flutter Web loads the CanvasKit renderer from `www.gstatic.com`. If
that CDN is unreachable (corporate proxy, firewall, flaky DNS) the engine never
boots and Chrome shows a blank page. Use the CanvasKit copy that ships with the
installed Flutter SDK instead:

```sh
flutter run -d chrome --no-web-resources-cdn
flutter build web --no-web-resources-cdn
```

With those flags the renderer is served from the local dev server / build output
(`canvaskit/`), so startup does not require any external download. Android and
iOS builds are unaffected.

Typography is bundled from `assets/fonts` (Inter 4.1, SIL OFL 1.1, see
`assets/fonts/Inter-LICENSE.txt`). The `Roboto` family in `pubspec.yaml` is
aliased to the same files because the CanvasKit renderer otherwise downloads
Roboto from `fonts.gstatic.com` on every startup.
