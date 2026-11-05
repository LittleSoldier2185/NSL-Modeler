import 'dart:convert';
import 'dart:io';

import '../models/workspace.dart';
import 'project_codec.dart';

/// เหตุที่เก็บสำเนา
enum SnapshotKind {
  /// เก็บตอนผู้ใช้กดบันทึก
  save,

  /// เก็บก่อนทิ้งงานที่ยังไม่บันทึก (เปิดไฟล์อื่น/โปรเจกต์ใหม่/นำเข้า แล้วเลือก "ไม่บันทึก")
  discarded,

  /// เก็บก่อนกู้คืนเวอร์ชันเก่าหรือรวมการแก้ไข เพื่อให้ย้อนกลับได้
  beforeRestore,

  /// ผู้ใช้สั่งเก็บเอง
  manual,

  /// เก็บตอนพบว่าไฟล์ถูกแก้จากภายนอก (ฐานเดิมของการรวมแบบ 3 ทาง)
  external,
}

class SnapshotInfo {
  const SnapshotInfo({
    required this.id,
    required this.savedAt,
    required this.kind,
    required this.label,
    required this.tables,
    required this.relations,
    required this.digest,
    this.documents,
  });

  /// ชื่อไฟล์ (ไม่รวมนามสกุล) — เรียงตามเวลาได้ด้วยการเทียบสตริง
  final String id;
  final DateTime savedAt;
  final SnapshotKind kind;
  final String label;
  final int tables;
  final int relations;

  /// จำนวนเอกสารในโปรเจกต์ (null = สำเนาจากโปรแกรมรุ่นเก่าที่ไม่ได้จดไว้)
  final int? documents;

  /// ลายนิ้วมือของเนื้อหา ใช้ตรวจว่าเหมือนเวอร์ชันล่าสุดหรือไม่
  final String digest;
}

/// เก็บสำเนาโปรเจกต์ย้อนหลังเป็นไฟล์ในโฟลเดอร์ [root] แยกโฟลเดอร์ย่อยตามไฟล์โปรเจกต์
/// ทุกสำเนาเป็นไฟล์ JSON เดี่ยว ๆ เขียนผ่านไฟล์ชั่วคราวแล้ว rename — ไฟล์เสียหนึ่งไฟล์ไม่กระทบไฟล์อื่น
class HistoryStore {
  HistoryStore(this.root, {this.maxPerProject = 60});

  final Directory root;

  /// เก็บอย่างมากต่อโปรเจกต์ — เกินแล้วลบอันเก่าสุด (สำเนา manual/beforeRestore ไม่ถูกลบก่อนเวลา ถ้ายังมีอย่างอื่นให้ลบ)
  final int maxPerProject;

  static const _fmt = 'nsl-snapshot';

  /// คีย์ของโปรเจกต์จาก path (ไม่สนตัวพิมพ์ใหญ่เล็กและชนิดของ \ /) ; null = ยังไม่เคยบันทึก
  static String keyFor(String? path) {
    if (path == null || path.isEmpty) return 'unsaved';
    final norm = path.replaceAll('\\', '/').toLowerCase();
    return 'p${_fnv(norm)}';
  }

  /// FNV-1a 64 บิต (แบ่ง 2 ท่อน 32 บิตให้ใช้ได้ทั้ง web/native โดยไม่ต้องใช้ BigInt)
  static String _fnv(String s) {
    var h1 = 0x811c9dc5, h2 = 0x01000193;
    for (final u in utf8.encode(s)) {
      h1 = ((h1 ^ u) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 ^ u) * 0x85ebca6b + h1) & 0xFFFFFFFF;
    }
    return h1.toRadixString(16).padLeft(8, '0') + h2.toRadixString(16).padLeft(8, '0');
  }

  /// ลายนิ้วมือเนื้อหาโปรเจกต์ทั้งหมด (รวมตำแหน่ง/สี — เปลี่ยนอะไรก็นับว่าเปลี่ยน)
  static String digestOf(Workspace w) => _fnv(jsonEncode(encodeProjectMap(w)));

  Directory _dir(String key) => Directory('${root.path}${Platform.pathSeparator}$key');
  File _file(String key, String id) => File('${_dir(key).path}${Platform.pathSeparator}$id.json');

  /// เก็บสำเนา คืน null ถ้าเหมือนสำเนาล่าสุดทุกประการ (ไม่เก็บซ้ำ) — [force] = เก็บเสมอ
  Future<SnapshotInfo?> add(
    String key,
    Workspace w, {
    SnapshotKind kind = SnapshotKind.save,
    String label = '',
    DateTime? now,
    bool force = false,
  }) async {
    final digest = digestOf(w);
    final existing = await list(key);
    if (!force && existing.isNotEmpty && existing.first.digest == digest) return null;

    final at = (now ?? DateTime.now()).toUtc();
    var id = '${at.year.toString().padLeft(4, '0')}${_pad2(at.month)}${_pad2(at.day)}-${_pad2(at.hour)}${_pad2(at.minute)}${_pad2(at.second)}'
        '-${at.millisecond.toString().padLeft(3, '0')}';
    // เวลาเดียวกัน (ms) ซ้ำ: ต่อเลขท้ายให้ไม่ทับกัน และยังเรียงตามเวลาถูก
    for (var n = 2; await _file(key, id).exists(); n++) {
      id = '${id.split('~').first}~$n';
    }

    await _dir(key).create(recursive: true);
    final body = jsonEncode({
      'format': _fmt,
      'savedAt': at.toIso8601String(),
      'kind': kind.name,
      'label': label,
      'digest': digest,
      // จำนวนตาราง/FK รวมทุกเอกสาร ER (คีย์เดิม — รายการประวัติของโปรแกรมรุ่นเก่ายังอ่านได้)
      'tables': w.tableCount,
      'relations': w.relationCount,
      'documents': w.documents.length,
      'project': encodeProjectMap(w),
    });
    final f = _file(key, id);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(f.path);
    await _prune(key);
    return SnapshotInfo(
      id: id,
      savedAt: at.toLocal(),
      kind: kind,
      label: label,
      tables: w.tableCount,
      relations: w.relationCount,
      digest: digest,
      documents: w.documents.length,
    );
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  /// รายการสำเนาของโปรเจกต์ ใหม่สุดก่อน (ข้ามไฟล์ที่เสีย)
  Future<List<SnapshotInfo>> list(String key) async {
    final d = _dir(key);
    if (!await d.exists()) return [];
    final out = <SnapshotInfo>[];
    await for (final e in d.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      final id = e.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), '');
      try {
        final j = jsonDecode(await e.readAsString()) as Map<String, dynamic>;
        if (j['format'] != _fmt) continue;
        out.add(SnapshotInfo(
          id: id,
          savedAt: DateTime.parse(j['savedAt'] as String).toLocal(),
          kind: SnapshotKind.values.asNameMap()[j['kind']] ?? SnapshotKind.save,
          label: j['label'] as String? ?? '',
          tables: (j['tables'] as num?)?.toInt() ?? 0,
          relations: (j['relations'] as num?)?.toInt() ?? 0,
          digest: j['digest'] as String? ?? '',
          documents: (j['documents'] as num?)?.toInt(),
        ));
      } catch (_) {}
    }
    out.sort((a, b) {
      final c = b.savedAt.compareTo(a.savedAt);
      return c != 0 ? c : b.id.compareTo(a.id);
    });
    return out;
  }

  /// อ่านสำเนากลับเป็นโปรเจกต์ ; null = ไม่พบ/ไฟล์เสีย
  Future<Workspace?> load(String key, String id) async {
    final f = _file(key, id);
    try {
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (j['format'] != _fmt) return null;
      return decodeProjectMap(j['project'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String key, String id) async {
    try {
      final f = _file(key, id);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// ย้ายประวัติของโปรเจกต์ที่ยังไม่เคยบันทึก ([keyFor] null) ไปอยู่กับไฟล์ที่เพิ่งบันทึกครั้งแรก/บันทึกเป็นชื่อใหม่
  Future<void> adopt(String fromKey, String toKey) async {
    if (fromKey == toKey) return;
    final from = _dir(fromKey);
    if (!await from.exists()) return;
    await _dir(toKey).create(recursive: true);
    await for (final e in from.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      final name = e.uri.pathSegments.last;
      final dest = File('${_dir(toKey).path}${Platform.pathSeparator}$name');
      try {
        if (!await dest.exists()) await e.rename(dest.path);
      } catch (_) {}
    }
  }

  Future<void> _prune(String key) async {
    final all = await list(key);
    if (all.length <= maxPerProject) return;
    // ลบอันเก่าสุดก่อน แต่เก็บ manual/beforeRestore ไว้ถ้ายังมีอย่างอื่นให้ลบ
    final removable = all.reversed.toList();
    var excess = all.length - maxPerProject;
    for (final pass in [false, true]) {
      for (final s in removable) {
        if (excess <= 0) break;
        final precious = s.kind == SnapshotKind.manual || s.kind == SnapshotKind.beforeRestore;
        if (precious && !pass) continue;
        await delete(key, s.id);
        excess--;
      }
    }
  }
}
