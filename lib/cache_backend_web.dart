import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'cache_backend_base.dart';

CacheBackend createBackend() => WebCacheBackend();

// ---------------------------------------------------------------------------
// Minimal bindings for the browser Cache Storage API (window.caches).
// This is the same storage a web app / service worker uses for cached files.
// ---------------------------------------------------------------------------
@JS('caches')
external _CacheStorage get _caches;

extension type _CacheStorage._(JSObject _) implements JSObject {
  external JSPromise<_Cache> open(String cacheName);
  external JSPromise<JSBoolean> delete(String cacheName);
  external JSPromise<JSBoolean> has(String cacheName);
}

extension type _Cache._(JSObject _) implements JSObject {
  external JSPromise<JSArray<_Request>> keys();
  external JSPromise<_Response?> match(String request);
  external JSPromise<JSAny?> put(String request, _Response response);
}

extension type _Request._(JSObject _) implements JSObject {
  external String get url;
}

@JS('Response')
extension type _Response._(JSObject _) implements JSObject {
  external _Response(JSAny? body);
  external JSPromise<_Blob> blob();
}

extension type _Blob._(JSObject _) implements JSObject {
  external double get size;
}

/// Web: each category is its own Cache Storage cache named `app_cache_<id>`.
/// Measuring reads entry sizes; clearing deletes the whole cache.
class WebCacheBackend implements CacheBackend {
  @override
  String get locationLabel => 'Browser Cache Storage';

  String _name(String id) => 'app_cache_$id';

  @override
  Future<void> init(List<String> categoryIds) async {
    if (!globalContext.has('caches')) {
      throw StateError(
        'Browser Cache Storage is not available here. '
        'Open the app on localhost or over HTTPS.',
      );
    }
  }

  @override
  Future<int> sizeOf(String categoryId) async {
    final name = _name(categoryId);
    // Check first so measuring never creates empty caches.
    final exists = (await _caches.has(name).toDart).toDart;
    if (!exists) return 0;

    final cache = await _caches.open(name).toDart;
    final requests = (await cache.keys().toDart).toDart;
    var total = 0;
    for (final request in requests) {
      final response = await cache.match(request.url).toDart;
      if (response == null) continue;
      final blob = await response.blob().toDart;
      total += blob.size.toInt();
    }
    return total;
  }

  @override
  Future<void> clear(String categoryId) async {
    await _caches.delete(_name(categoryId)).toDart;
  }

  @override
  Future<void> writeDemo(String categoryId, int bytes) async {
    final cache = await _caches.open(_name(categoryId)).toDart;
    final chunk = Uint8List(1024 * 1024);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    var remaining = bytes;
    var part = 0;
    while (remaining > 0) {
      final size = remaining < chunk.length ? remaining : chunk.length;
      final body = Uint8List.sublistView(chunk, 0, size).toJS;
      final url = Uri.base
          .resolve('app_cache/$categoryId/demo_${stamp}_${part++}.bin')
          .toString();
      await cache.put(url, _Response(body)).toDart;
      remaining -= size;
    }
  }
}
