import 'dart:io';

/// รายชื่อฟอนต์ (family) ที่ติดตั้งในเครื่อง ใช้ให้ผู้ใช้เลือกฟอนต์ของตาราง
///
/// Windows อ่านจากรีจิสทรี, Linux ใช้ `fc-list`, macOS ไล่ดูโฟลเดอร์ฟอนต์
/// ผลลัพธ์ถูกแคชไว้ และเปลี่ยนตัวโหลดได้ (ใช้ในเทสต์)
class SystemFonts {
  SystemFonts._();

  /// ตัวโหลดรายชื่อ — เปลี่ยนได้ในเทสต์
  static Future<List<String>> Function() loader = _defaultLoad;
  static List<String>? _cache;

  static Future<List<String>> list() async {
    if (_cache != null) return _cache!;
    try {
      _cache = await loader();
    } catch (_) {
      _cache = const [];
    }
    return _cache!;
  }

  static void resetCache() => _cache = null;

  static Future<List<String>> _defaultLoad() async {
    if (Platform.isWindows) {
      final lines = <String>[];
      for (final hive in ['HKLM', 'HKCU']) {
        final r = await Process.run('reg', ['query', '$hive\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Fonts']);
        if (r.exitCode == 0) lines.addAll((r.stdout as String).split(RegExp(r'\r?\n')));
      }
      return parseWindowsRegistry(lines);
    }
    if (Platform.isLinux) {
      final r = await Process.run('fc-list', [':', 'family']);
      return r.exitCode == 0 ? parseFcList((r.stdout as String).split('\n')) : const [];
    }
    if (Platform.isMacOS) {
      final names = <String>[];
      for (final dir in ['/System/Library/Fonts', '/Library/Fonts']) {
        final d = Directory(dir);
        if (!d.existsSync()) continue;
        for (final f in d.listSync()) {
          final base = f.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
          final dot = base.lastIndexOf('.');
          if (dot > 0) names.add(base.substring(0, dot));
        }
      }
      return _clean(names);
    }
    return const [];
  }

  static final _styleWords = RegExp(
      r'\s+(Bold Italic|Bold Oblique|Semibold Italic|Light Italic|Demi Bold|Bold|Italic|Oblique|Regular)$',
      caseSensitive: false);

  /// แถวของ `reg query` เช่น `    Arial Bold (TrueType)    REG_SZ    arialbd.ttf`
  static List<String> parseWindowsRegistry(Iterable<String> lines) {
    final names = <String>[];
    for (final line in lines) {
      final m = RegExp(r'^\s+(.+?)\s+REG_\w+\s+').firstMatch(line);
      if (m == null) continue;
      final n = m.group(1)!.replaceFirst(RegExp(r'\s*\((TrueType|OpenType|All res)\)\s*$', caseSensitive: false), '');
      // ไฟล์รวม เช่น "Cambria & Cambria Math"
      names.addAll(n.split(' & '));
    }
    return _clean(names);
  }

  /// ผลของ `fc-list : family` — แต่ละบรรทัดอาจมีหลายชื่อคั่นด้วยจุลภาค
  static List<String> parseFcList(Iterable<String> lines) => _clean([for (final l in lines) ...l.split(',')]);

  static List<String> _clean(Iterable<String> raw) {
    final seen = <String, String>{};
    for (var n in raw) {
      n = n.trim();
      // ตัดคำบอกสไตล์ท้ายชื่อให้เหลือ family
      n = n.replaceFirst(_styleWords, '');
      if (n.isEmpty || n.startsWith('@') || n.startsWith('.')) continue;
      seen.putIfAbsent(n.toLowerCase(), () => n);
    }
    return seen.values.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}
