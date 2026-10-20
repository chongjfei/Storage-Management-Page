/// Where cache data physically lives. One implementation per platform:
/// device files (mobile/desktop) and the browser's Cache Storage (web).
abstract class CacheBackend {
  /// Short, human-readable description shown on the Storage page.
  String get locationLabel;

  /// Prepares storage for the given category ids. Throws if unavailable.
  Future<void> init(List<String> categoryIds);

  /// Total bytes currently stored for one category.
  Future<int> sizeOf(String categoryId);

  /// Deletes everything stored for one category.
  Future<void> clear(String categoryId);

  /// DEMO ONLY: stores [bytes] of dummy data in one category.
  Future<void> writeDemo(String categoryId, int bytes);
}
