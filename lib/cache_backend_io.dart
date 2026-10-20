import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'cache_backend_base.dart';

CacheBackend createBackend() => IoCacheBackend();

/// Mobile/desktop: each category is a folder under <temp dir>/app_cache/.
class IoCacheBackend implements CacheBackend {
  Directory? _root;

  @override
  String get locationLabel => 'App cache folder on this device';

  Directory _dir(String id) => Directory('${_root!.path}/$id');

  @override
  Future<void> init(List<String> categoryIds) async {
    final base = await getTemporaryDirectory();
    _root = Directory('${base.path}/app_cache');
    for (final id in categoryIds) {
      await _dir(id).create(recursive: true);
    }
  }

  @override
  Future<int> sizeOf(String categoryId) async {
    final dir = _dir(categoryId);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          // File vanished while measuring; ignore.
        }
      }
    }
    return total;
  }

  @override
  Future<void> clear(String categoryId) async {
    final dir = _dir(categoryId);
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {
        // A file in use can't be deleted; skip it.
      }
    }
  }

  @override
  Future<void> writeDemo(String categoryId, int bytes) async {
    final dir = _dir(categoryId);
    final chunk = Uint8List(1024 * 1024);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    var remaining = bytes;
    var part = 0;
    while (remaining > 0) {
      final size = min(remaining, chunk.length);
      final file = File('${dir.path}/demo_${stamp}_${part++}.bin');
      await file.writeAsBytes(Uint8List.sublistView(chunk, 0, size), flush: true);
      remaining -= size;
    }
  }
}
