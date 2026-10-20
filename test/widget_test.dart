import 'package:flutter_test/flutter_test.dart';
import 'package:storage_ui/cache_backend.dart';
import 'package:storage_ui/main.dart';

/// In-memory backend so the controller logic can be tested on any platform,
/// including `flutter test --platform chrome`.
class FakeBackend implements CacheBackend {
  final Map<String, int> _bytes = {};

  @override
  String get locationLabel => 'Fake storage';

  @override
  Future<void> init(List<String> categoryIds) async {
    for (final id in categoryIds) {
      _bytes[id] = 0;
    }
  }

  @override
  Future<int> sizeOf(String categoryId) async => _bytes[categoryId] ?? 0;

  @override
  Future<void> clear(String categoryId) async {
    _bytes[categoryId] = 0;
  }

  @override
  Future<void> writeDemo(String categoryId, int bytes) async {
    _bytes[categoryId] = (_bytes[categoryId] ?? 0) + bytes;
  }
}

void main() {
  late CacheController controller;

  setUp(() async {
    controller = CacheController(backend: FakeBackend());
    await controller.init();
  });

  test('starts empty and healthy', () {
    expect(controller.loading, isFalse);
    expect(controller.error, isNull);
    expect(controller.usedBytes, 0);
    expect(controller.level, StorageLevel.healthy);
  });

  test('85% of the limit is almost full', () async {
    await controller.addDemoData((CacheController.limitBytes * 0.85).round());
    expect(controller.level, StorageLevel.almostFull);
  });

  test('reaching the limit is full', () async {
    await controller.addDemoData(CacheController.limitBytes + 1024 * 1024);
    expect(controller.level, StorageLevel.full);
    expect(controller.usedPercent, 100);
    expect(controller.freeBytes, 0);
  });

  test('clearing one category leaves the others', () async {
    await controller.addDemoData(10 * 1024 * 1024);
    final images = controller.categories.first;
    final before = controller.usedBytes;
    final imageBytes = images.bytes;

    final freed = await controller.clear(images);

    expect(freed, imageBytes);
    expect(images.bytes, 0);
    expect(controller.usedBytes, before - imageBytes);
    expect(controller.usedBytes, greaterThan(0));
  });

  test('clear all frees everything and returns to healthy', () async {
    await controller.addDemoData(CacheController.limitBytes + 1024 * 1024);
    final before = controller.usedBytes;

    final freed = await controller.clearAll();

    expect(freed, before);
    expect(controller.usedBytes, 0);
    expect(controller.level, StorageLevel.healthy);
    expect(controller.busy, isFalse);
  });
}
