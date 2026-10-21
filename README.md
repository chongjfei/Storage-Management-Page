# Storage Management Page (Flutter: web, Android, iOS, desktop)

A storage management screen for an app's Settings page. When the app's cache
reaches its limit the app can stop working, so the user can open
**Settings → Storage** and delete cache data to free space.

## Features

- **Settings entry** with a status badge ("94% full" / "Full") when storage is running low
- **Usage meter** showing cache used vs. the limit, split by category
- **Three states:** Healthy, Almost full (80%+), Full (100%)
- **Cache breakdown** by category: image cache, offline downloads, temporary files, search history, logs
- **Clear one category** or **Clear all cache**, with a confirmation sheet before deleting
- **Real storage on every platform** (see below), not mock numbers
- **Responsive:** on wide browser windows the page stays in a phone-width column

## Where the cache lives

| Platform | Storage | Implementation |
| --- | --- | --- |
| Web | Browser **Cache Storage** (`window.caches`), one cache per category | `lib/cache_backend_web.dart` |
| Android / iOS / desktop | Folders under the app's temp directory (`path_provider`) | `lib/cache_backend_io.dart` |

The UI only talks to the `CacheBackend` interface (`lib/cache_backend_base.dart`).
`lib/cache_backend.dart` picks the right implementation at compile time, so
there is no `dart:io` in the web build.

> Browser Cache Storage needs a **secure context**: `localhost` or HTTPS. On
> plain `http://` over a network address the page shows an error with a
> "Try again" button instead of crashing.

## Run it

```
flutter pub get
flutter run -d chrome        # web
flutter run                  # emulator / device
```

Build for web: `flutter build web` (output in `build/web`; serve it over
`localhost` or HTTPS, not by opening `index.html` directly).

## Try the flow

The cache starts empty, so use the demo menu to create some data:

1. Open **Settings → Storage**.
2. Tap the flask icon (top right) → **Fill to limit**.
3. The meter, status chip and banner update to **Full**.
4. Tap **Clear** on a row, or **Clear all cache** and confirm. The data is
   deleted and the status returns to **Healthy**.

On web you can watch it happen: open DevTools → **Application → Cache Storage**.
The `app_cache_images`, `app_cache_downloads`, ... entries appear when you
fill the cache and disappear when you clear it.

The flask menu is for demonstration; remove it in a production app.

## Tests

```
flutter test                    # runs on the Dart VM
flutter test --platform chrome  # runs compiled for web
```

`test/widget_test.dart` covers the limit logic (healthy / almost full / full)
and clearing one category or all of them, using an in-memory backend.

## Brand colors

All colors live in `AppColors` at the top of `lib/main.dart`.

| Token | Hex | Used for |
| --- | --- | --- |
| `brand` | `#0E8F82` | Teal: icons, meter segments, identity |
| `brandDeep` | `#08786D` | Deep teal: filled buttons (white text passes AA contrast) |
| `gold` | `#F8E692` | Soft gold: "Almost full" badge and warning |
| `ground` | `#F5FAF9` | Mint-white page background |
| `ink` | `#183C38` | Dark green primary text |

Secondary text, dividers and the empty meter track are tints derived from the
same green. "Full" keeps a red because the palette has no error color.

## Configuration

- `CacheController.limitBytes` sets the cache limit (50 MB for the demo).
- Category ids (`images`, `downloads`, `temp`, `search`, `logs`) are the
  folder names on mobile/desktop and the cache names (`app_cache_<id>`) on web.
  Point them at what your app really stores.
- To stop the app saving at the limit, check
  `controller.level == StorageLevel.full` before writing.

## Structure

```
lib/
  main.dart                  UI + CacheController (limit logic)
  cache_backend_base.dart    CacheBackend interface
  cache_backend.dart         picks the backend per platform
  cache_backend_io.dart      device files (mobile / desktop)
  cache_backend_web.dart     browser Cache Storage (web)
  cache_backend_stub.dart    fallback
test/
  widget_test.dart           controller tests
```
