// Picks the right storage backend at compile time:
//  - web (dart:js_interop available)  -> cache_backend_web.dart
//  - mobile/desktop (dart:io available) -> cache_backend_io.dart
// The web branch is listed first so it wins on Flutter web.
export 'cache_backend_base.dart';
export 'cache_backend_stub.dart'
    if (dart.library.js_interop) 'cache_backend_web.dart'
    if (dart.library.io) 'cache_backend_io.dart';
