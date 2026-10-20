import 'dart:math';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'cache_backend.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StorageDemoApp());
}

// ---------------------------------------------------------------------------
// Colors
// ---------------------------------------------------------------------------
class AppColors {
  static const ground = Color(0xFFF4F2EC);
  static const ink = Color(0xFF1A1D1C);
  static const muted = Color(0xFF5B605E);
  static const subtle = Color(0xFF6B706D);
  static const hairline = Color(0xFFEFEDE6);
  static const track = Color(0xFFE7E4DA);
  static const accent = Color(0xFF0E5C4D);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
String formatBytes(int bytes) {
  const kb = 1024;
  const mb = 1024 * 1024;
  if (bytes >= mb) {
    final v = bytes / mb;
    return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} MB';
  }
  if (bytes >= kb) return '${(bytes / kb).round()} KB';
  return '$bytes B';
}

enum StorageLevel { healthy, almostFull, full }

class _LevelStyle {
  const _LevelStyle({
    required this.label,
    required this.banner,
    required this.chip,
    required this.text,
    required this.icon,
    required this.iconData,
    required this.headline,
    required this.message,
  });

  final String label;
  final Color banner;
  final Color chip;
  final Color text;
  final Color icon;
  final IconData iconData;
  final String headline;
  final String message;
}

_LevelStyle _styleFor(StorageLevel level) {
  switch (level) {
    case StorageLevel.healthy:
      return const _LevelStyle(
        label: 'Healthy',
        banner: Color(0xFFDDF0E8),
        chip: Color(0xFFDDF0E8),
        text: Color(0xFF0B4F44),
        icon: Color(0xFF0B4F44),
        iconData: Icons.check_circle_outline,
        headline: 'Storage is healthy. ',
        message: 'The app has room to save new data.',
      );
    case StorageLevel.almostFull:
      return const _LevelStyle(
        label: 'Almost full',
        banner: Color(0xFFFDEBD6),
        chip: Color(0xFFFBE3C8),
        text: Color(0xFF6B2A0B),
        icon: Color(0xFFB4470F),
        iconData: Icons.warning_amber_rounded,
        headline: 'Storage is almost full. ',
        message:
            "When it reaches the limit, the app can't save new data. Clear cache to keep it running.",
      );
    case StorageLevel.full:
      return const _LevelStyle(
        label: 'Full',
        banner: Color(0xFFFADBD3),
        chip: Color(0xFFF6C9BE),
        text: Color(0xFF6E1A0E),
        icon: Color(0xFFB3261E),
        iconData: Icons.error_outline,
        headline: 'Storage is full. ',
        message: "The app can't save new data until you clear some cache.",
      );
  }
}

// ---------------------------------------------------------------------------
// Data + real file handling
// ---------------------------------------------------------------------------
class CacheCategory {
  CacheCategory({
    required this.id,
    required this.name,
    required this.note,
    required this.color,
  });

  /// Also the storage key (folder / cache name) for this category.
  final String id;
  final String name;
  final String note;
  final Color color;
  int bytes = 0;
}

class CacheController extends ChangeNotifier {
  CacheController({CacheBackend? backend}) : _backend = backend ?? createBackend();

  /// Demo limit (50 MB) so you can fill it quickly while testing.
  /// Replace with your app's real cache limit.
  static const int limitBytes = 50 * 1024 * 1024;

  final CacheBackend _backend;

  final List<CacheCategory> categories = [
    CacheCategory(
      id: 'images',
      name: 'Image cache',
      note: 'Photos, thumbnails',
      color: const Color(0xFF0B4F44),
    ),
    CacheCategory(
      id: 'downloads',
      name: 'Offline downloads',
      note: 'Saved for offline use',
      color: const Color(0xFF2A7F6E),
    ),
    CacheCategory(
      id: 'temp',
      name: 'Temporary files',
      note: 'Leftover edit files',
      color: const Color(0xFF5BA897),
    ),
    CacheCategory(
      id: 'search',
      name: 'Search history',
      note: 'Recent searches',
      color: const Color(0xFF94CBBD),
    ),
    CacheCategory(
      id: 'logs',
      name: 'Logs and diagnostics',
      note: 'Sync and crash logs',
      color: const Color(0xFFC9E6DE),
    ),
  ];

  bool loading = true;
  bool busy = false;
  String? error;

  String get locationLabel => _backend.locationLabel;

  int get usedBytes => categories.fold(0, (sum, c) => sum + c.bytes);
  int get freeBytes => max(0, limitBytes - usedBytes);
  double get usedFraction => usedBytes / limitBytes;
  int get usedPercent => min(100, max(0, (usedFraction * 100).round()));

  StorageLevel get level {
    if (usedBytes >= limitBytes) return StorageLevel.full;
    if (usedFraction >= 0.8) return StorageLevel.almostFull;
    return StorageLevel.healthy;
  }

  /// Prepares the backend and measures every category.
  Future<void> init() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _backend.init([for (final c in categories) c.id]);
      await _measure();
    } catch (e) {
      error = 'Could not read the cache: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _measure() async {
    for (final c in categories) {
      c.bytes = await _backend.sizeOf(c.id);
    }
  }

  /// Runs a storage operation with the busy flag, then re-measures.
  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      await action();
      await _measure();
    } catch (e) {
      error = 'Storage operation failed: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Deletes everything in one category. Returns the bytes actually freed.
  Future<int> clear(CacheCategory category) async {
    final before = category.bytes;
    await _run(() => _backend.clear(category.id));
    return before - category.bytes;
  }

  /// Deletes everything in every category. Returns the bytes actually freed.
  Future<int> clearAll() async {
    final before = usedBytes;
    await _run(() async {
      for (final c in categories) {
        await _backend.clear(c.id);
      }
    });
    return before - usedBytes;
  }

  /// DEMO ONLY: stores dummy data so there is something to clear.
  Future<void> addDemoData(int totalBytes) async {
    if (totalBytes <= 0) return;
    const weights = [0.45, 0.30, 0.15, 0.06, 0.04];
    await _run(() async {
      for (var i = 0; i < categories.length; i++) {
        final bytes = (totalBytes * weights[i]).round();
        if (bytes > 0) await _backend.writeDemo(categories[i].id, bytes);
      }
    });
  }
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------
class StorageDemoApp extends StatefulWidget {
  const StorageDemoApp({super.key});

  @override
  State<StorageDemoApp> createState() => _StorageDemoAppState();
}

class _StorageDemoAppState extends State<StorageDemoApp> {
  final CacheController controller = CacheController();

  @override
  void initState() {
    super.initState();
    controller.init();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Storage Management',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent),
        scaffoldBackgroundColor: AppColors.ground,
      ),
      // On wide browser windows keep the page in a phone-width column
      // instead of stretching every row across the whole screen.
      builder: (context, child) => ColoredBox(
        color: const Color(0xFFE9E6DC),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: child,
          ),
        ),
      ),
      home: SettingsScreen(controller: controller),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 1: Settings
// ---------------------------------------------------------------------------
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final CacheController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          children: [
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('Account', top: 0),
            const _Group(children: [
              _SettingsTile(icon: Icons.person_outline, title: 'Profile'),
            ]),
            const _SectionLabel('Preferences'),
            const _Group(children: [
              _SettingsTile(icon: Icons.notifications_none, title: 'Notifications'),
              _SettingsTile(icon: Icons.wb_sunny_outlined, title: 'Appearance'),
            ]),
            const _SectionLabel('App'),
            _Group(children: [
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final level = controller.level;
                  final style = _styleFor(level);
                  String? badge;
                  if (level == StorageLevel.full) {
                    badge = 'Full';
                  } else if (level == StorageLevel.almostFull) {
                    badge = '${controller.usedPercent}% full';
                  }
                  return _SettingsTile(
                    icon: Icons.storage_outlined,
                    title: 'Storage',
                    badge: badge,
                    badgeBackground: style.chip,
                    badgeForeground: style.text,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StorageScreen(controller: controller),
                      ),
                    ),
                  );
                },
              ),
              const _SettingsTile(icon: Icons.shield_outlined, title: 'Privacy'),
              const _SettingsTile(icon: Icons.info_outline, title: 'About'),
            ]),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.badge,
    this.badgeBackground = const Color(0xFFFBE3C8),
    this.badgeForeground = const Color(0xFF6B2A0B),
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? badge;
  final Color badgeBackground;
  final Color badgeForeground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap ?? () {},
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.ink),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (badge != null) ...[
                _Chip(
                  text: badge!,
                  background: badgeBackground,
                  foreground: badgeForeground,
                ),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.chevron_right, color: AppColors.subtle),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 2: Storage
// ---------------------------------------------------------------------------
class StorageScreen extends StatelessWidget {
  const StorageScreen({super.key, required this.controller});

  final CacheController controller;

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ClearConfirmSheet(controller: controller),
    );
    if (confirmed == true) {
      final freed = await controller.clearAll();
      if (context.mounted) _toast(context, '${formatBytes(freed)} cleared');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final used = controller.usedBytes;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.ground,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            title: const Text(
              'Storage',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            actions: [
              // DEMO ONLY: remove in a real app.
              PopupMenuButton<String>(
                tooltip: 'Demo data',
                icon: const Icon(Icons.science_outlined),
                onSelected: (value) {
                  if (value == 'add') {
                    controller.addDemoData(10 * 1024 * 1024);
                  } else {
                    controller.addDemoData(
                      CacheController.limitBytes - controller.usedBytes,
                    );
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'add', child: Text('Add 10 MB demo data')),
                  PopupMenuItem(value: 'fill', child: Text('Fill to limit')),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: controller.loading
                ? const Center(child: CircularProgressIndicator())
                : controller.error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(controller.error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: controller.init,
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                              children: [
                                if (controller.busy)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 8),
                                    child: LinearProgressIndicator(minHeight: 3),
                                  ),
                                _MeterCard(controller: controller),
                                const SizedBox(height: 12),
                                _StatusBanner(level: controller.level),
                                const _SectionLabel('Cache breakdown'),
                                _Group(children: [
                                  for (final category in controller.categories)
                                    _CacheRow(
                                      category: category,
                                      busy: controller.busy,
                                      onClear: () async {
                                        final name = category.name;
                                        final freed = await controller.clear(category);
                                        if (context.mounted) {
                                          _toast(
                                            context,
                                            '$name cleared (${formatBytes(freed)})',
                                          );
                                        }
                                      },
                                    ),
                                ]),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: FilledButton(
                                    onPressed: (used > 0 && !controller.busy)
                                        ? () => _confirmClearAll(context)
                                        : null,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: AppColors.track,
                                      disabledForegroundColor: AppColors.muted,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    child: Text(
                                      used > 0
                                          ? 'Clear all cache · ${formatBytes(used)}'
                                          : 'Nothing to clear',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  used > 0
                                      ? 'Your tasks and account data are never deleted.'
                                      : 'Cache rebuilds as you use the app.',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
          ),
        );
      },
    );
  }
}

class _MeterCard extends StatelessWidget {
  const _MeterCard({required this.controller});

  final CacheController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final style = _styleFor(c.level);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cache used',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatBytes(c.usedBytes),
                      style: const TextStyle(
                        fontSize: 40,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                        color: AppColors.ink,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      'of ${formatBytes(CacheController.limitBytes)} limit',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              _Chip(
                text: style.label,
                background: style.chip,
                foreground: style.text,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SegmentedBar(controller: c),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${c.usedPercent}% used',
                style: const TextStyle(fontSize: 14, color: AppColors.muted),
              ),
              Text(
                '${formatBytes(c.freeBytes)} free',
                style: const TextStyle(fontSize: 14, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Stored in: ${c.locationLabel}',
            style: const TextStyle(fontSize: 13, color: AppColors.subtle),
          ),
        ],
      ),
    );
  }
}

class _SegmentedBar extends StatelessWidget {
  const _SegmentedBar({required this.controller});

  final CacheController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    var flexSum = 0;
    final segments = <Widget>[];
    for (final cat in c.categories) {
      if (cat.bytes <= 0) continue;
      final flex = max(1, min(1000, (cat.bytes * 1000 / CacheController.limitBytes).round()));
      flexSum += flex;
      segments.add(
        Expanded(
          flex: flex,
          child: Container(
            decoration: BoxDecoration(
              color: cat.color,
              border: const Border(
                right: BorderSide(color: Colors.white, width: 2),
              ),
            ),
          ),
        ),
      );
    }
    if (flexSum < 1000) segments.add(Spacer(flex: 1000 - flexSum));

    return Semantics(
      label:
          '${formatBytes(c.usedBytes)} of ${formatBytes(CacheController.limitBytes)} used',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Container(
          height: 14,
          color: AppColors.track,
          child: Row(children: segments),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.level});

  final StorageLevel level;

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(level);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: style.banner,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(style.iconData, color: style.icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 14, height: 1.43, color: style.text),
                children: [
                  TextSpan(
                    text: style.headline,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: style.message),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CacheRow extends StatelessWidget {
  const _CacheRow({
    required this.category,
    required this.busy,
    required this.onClear,
  });

  final CacheCategory category;
  final bool busy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: category.color,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x24000000)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    '${formatBytes(category.bytes)} · ${category.note}',
                    style: const TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            if (category.bytes > 0)
              TextButton(
                onPressed: busy ? null : onClear,
                style: TextButton.styleFrom(
                  minimumSize: const Size(72, 44),
                  backgroundColor: AppColors.hairline,
                  foregroundColor: AppColors.ink,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Clear'),
              )
            else
              const SizedBox(
                width: 72,
                child: Center(
                  child: Text(
                    'Empty',
                    style: TextStyle(fontSize: 14, color: AppColors.subtle),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 3: Confirm bottom sheet
// ---------------------------------------------------------------------------
class _ClearConfirmSheet extends StatelessWidget {
  const _ClearConfirmSheet({required this.controller});

  final CacheController controller;

  @override
  Widget build(BuildContext context) {
    final total = formatBytes(controller.usedBytes);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D2C6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Clear all cache?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'This frees up $total. Your tasks and account data stay safe.',
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.ground,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  for (final c in controller.categories)
                    SizedBox(
                      height: 36,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            c.name,
                            style: const TextStyle(fontSize: 15, color: AppColors.ink),
                          ),
                          Text(
                            formatBytes(c.bytes),
                            style: const TextStyle(fontSize: 15, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Offline downloads will need to be downloaded again.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text('Clear $total'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.hairline,
                  foregroundColor: AppColors.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.top = 24});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: AppColors.muted,
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1, color: AppColors.hairline),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}
