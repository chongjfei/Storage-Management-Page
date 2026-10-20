import 'cache_backend_base.dart';

/// Fallback used only if neither web nor dart:io is available.
CacheBackend createBackend() =>
    throw UnsupportedError('No cache storage backend for this platform.');
