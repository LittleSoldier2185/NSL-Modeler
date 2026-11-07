import 'dart:convert';

import '../l10n/l10n.dart';
import '../models/dfd_model.dart';
import '../models/diagram.dart';
import '../models/flowchart_model.dart';
import '../models/project.dart';
import '../models/workspace.dart';
import 'project_format_exception.dart';

export 'project_format_exception.dart';

/// เวอร์ชันรูปแบบไฟล์ที่เขียน (v3 = workspace หลายเอกสาร) — อ่านได้ตั้งแต่ v1 ถึงค่านี้
const int kWorkspaceFormatVersion = 3;

/// ค่า `format` ของไฟล์โปรเจกต์ (คงเดิมตั้งแต่ v1)
const String kProjectFormatTag = 'nsl-erd';

/// ทางเข้าเดียวสำหรับแปลง JSON ของโปรเจกต์ (ไฟล์ / autosave / ประวัติ / เทียบเวอร์ชัน) เป็น [Workspace]
/// - v1/v2: เนื้อหา ER อ่านด้วย [Project.fromJson] ; แท็บ `diagrams` ซ่อมแล้วแปลงเป็นเอกสารตามลำดับเดิม
/// - v3: อ่านเอกสารทีละชิ้น ซ่อมข้อมูลผิดปกติ (id ซ้ำ, ชื่อว่าง/ซ้ำ, โฟลเดอร์เสีย/วน)
/// - v4 ขึ้นไป / ไม่ใช่ไฟล์โปรเจกต์: throw [ProjectFormatException]
Workspace decodeProjectMap(Map<String, dynamic> j) {
  if (j['format'] != kProjectFormatTag) {
    throw ProjectFormatException(tr('ไม่ใช่ไฟล์โปรเจกต์ NSL Dev'));
  }
  final v = j['version'];
  if (v is! int || v > kWorkspaceFormatVersion) {
    throw ProjectFormatException(tr('ไฟล์เวอร์ชันใหม่กว่าที่โปรแกรมรองรับ'));
  }
  final Workspace w;
  try {
    w = v < 3 ? _decodeLegacy(j) : _decodeV3(j);
  } on ProjectFormatException {
    rethrow;
  } catch (e) {
    throw ProjectFormatException(tr('โครงสร้างไฟล์ไม่ถูกต้อง: {0}', [e]));
  }
  _resolveTableDocs(w);
  return w;
}

/// JSON v3 ของ [w] (เขียน v3 เสมอ)
Map<String, dynamic> encodeProjectMap(Workspace w) => {
      'format': kProjectFormatTag,
      'version': kWorkspaceFormatVersion,
      'name': w.name,
      'meta': w.meta.toJson(),
      'folders': [for (final f in w.folders) f.toJson()],
      'documents': [
        for (final d in w.documents)
          {
            'id': d.id,
            'type': d.typeName,
            'name': d.name,
            if (d.folderId != null) 'folder': d.folderId,
            'typeVersion': d.typeVersion,
            ...d.extra,
            'content': d.content.toContentJson(),
          },
      ],
      'links': w.links,
    };

/// สำเนาแยกขาดของ [w] (ผ่าน JSON v3) — ใช้เก็บสถานะ ณ ขณะหนึ่ง เช่น auto-save
Workspace copyWorkspace(Workspace w) =>
    decodeProjectMap(jsonDecode(jsonEncode(encodeProjectMap(w))) as Map<String, dynamic>);

const _docKeys = {'id', 'type', 'name', 'folder', 'typeVersion', 'content'};

/// แท็บหนึ่งแท็บของไฟล์ v1/v2 (`diagrams`)
class _LegacyTab {
  _LegacyTab(this.id, this.name, this.isEr);
  final String id;
  String name;
  final bool isEr;
}

/// ไฟล์ v1/v2 -> workspace : เอกสารเรียงตามแท็บ ; ER ได้ id `er` ชื่อ = ชื่อแท็บ ER (ค่าเริ่มต้น "ER") ;
/// DFD ใช้ id เดิมของแท็บ (childId ยังชี้ถูก) แท็บที่ไม่มีเนื้อหาได้แผนภาพว่าง ; เนื้อหา `dfd` ที่ไม่มีแท็บถูกทิ้ง
Workspace _decodeLegacy(Map<String, dynamic> j) {
  final er = Project.fromJson(j);
  final dfd = j['dfd'] is Map ? j['dfd'] as Map : const {};
  return Workspace(
    name: er.name,
    documents: [
      for (final t in _legacyTabs(j['diagrams']))
        if (t.isEr)
          ProjectDocument.er(id: kErDiagramId, name: t.name, content: er)
        else
          ProjectDocument.dfd(id: t.id, name: t.name, content: DfdDiagram.fromJson(dfd[t.id])),
    ],
  );
}

/// ซ่อมรายการแท็บของไฟล์เก่า: มี ER อันเดียว (id = [kErDiagramId]), id ไม่ซ้ำ, ชื่อไม่ว่างและไม่ซ้ำ (ไม่สนตัวพิมพ์)
/// ค่าที่ผิดปกติ (ไม่ใช่ map / ไม่มี id / ชนิดไม่รู้จัก) ถูกข้าม ; ไม่มี ER = เพิ่มไว้หน้าสุด
List<_LegacyTab> _legacyTabs(Object? raw) {
  final out = <_LegacyTab>[];
  final ids = <String>{};
  var haveEr = false;
  for (final e in raw is List ? raw : const []) {
    if (e is! Map) continue;
    final id = e['id'], kind = e['kind'], n = e['name'];
    if (id is! String || id.isEmpty || (kind != 'er' && kind != 'dfd')) continue;
    final name = n is String ? cleanDiagramName(n) : '';
    if (kind == 'er') {
      if (haveEr) continue;
      haveEr = true;
      out.add(_LegacyTab(kErDiagramId, name, true));
      ids.add(kErDiagramId);
    } else {
      if (id == kErDiagramId || !ids.add(id)) continue;
      out.add(_LegacyTab(id, name, false));
    }
  }
  if (!haveEr) out.insert(0, _LegacyTab(kErDiagramId, '', true));

  final used = <String>{};
  for (final t in out) {
    var base = cleanDiagramName(t.name);
    if (base.isEmpty) base = t.isEr ? 'ER' : 'DFD';
    var name = base;
    for (var n = 2; used.contains(name.toLowerCase()); n++) {
      name = '$base $n';
    }
    used.add(name.toLowerCase());
    t.name = name;
  }
  return out;
}

Workspace _decodeV3(Map<String, dynamic> j) {
  final metaJ = j['meta'] is Map ? Map<String, dynamic>.from(j['meta'] as Map) : <String, dynamic>{};
  final desc = metaJ.remove('description'), created = metaJ.remove('createdAt');
  final meta = WorkspaceMeta(
    description: desc is String ? desc : '',
    createdAt: created is String ? created : null,
    extra: metaJ,
  );

  // โฟลเดอร์: ข้าม id ว่าง/ซ้ำ ; parent ที่ไม่มีอยู่หรือวนเป็นวง -> ราก
  final folders = <DocFolder>[];
  final fids = <String>{};
  for (final e in (j['folders'] is List ? j['folders'] as List : const [])) {
    if (e is! Map) continue;
    final id = e['id'];
    if (id is! String || id.isEmpty || !fids.add(id)) continue;
    final parent = e['parent'];
    folders.add(DocFolder(
      id: id,
      name: e['name'] is String ? e['name'] as String : '',
      parentId: parent is String && parent.isNotEmpty ? parent : null,
    ));
  }
  final byId = {for (final f in folders) f.id: f};
  for (final f in folders) {
    if (f.parentId != null && !byId.containsKey(f.parentId)) f.parentId = null;
  }
  for (final f in folders) {
    final seen = <String>{f.id};
    for (var p = f.parentId; p != null; p = byId[p]?.parentId) {
      if (!seen.add(p)) {
        f.parentId = null;
        break;
      }
    }
  }

  final docs = <ProjectDocument>[];
  final ids = <String>{};
  for (final e in (j['documents'] is List ? j['documents'] as List : const [])) {
    if (e is! Map) continue;
    final id = e['id'], type = e['type'];
    if (id is! String || id.isEmpty || type is! String || type.isEmpty || !ids.add(id)) continue;
    final raw = e['content'];
    final DocContent content = switch (DocType.values.asNameMap()[type]) {
      DocType.er => raw is Map ? Project.fromContentJson(Map<String, dynamic>.from(raw)) : Project(),
      DocType.dfd => DfdDiagram.fromJson(raw),
      DocType.flowchart => FlowchartDiagram.fromJson(raw),
      null => RawDocContent(raw),
    };
    final folder = e['folder'];
    final tv = e['typeVersion'];
    docs.add(ProjectDocument(
      id: id,
      typeName: type,
      name: e['name'] is String ? e['name'] as String : '',
      folderId: folder is String && byId.containsKey(folder) ? folder : null,
      typeVersion: tv is int && tv > 0 ? tv : 1,
      content: content,
      extra: {
        for (final x in e.entries)
          if (x.key is String && !_docKeys.contains(x.key)) x.key as String: x.value,
      },
    ));
  }
  _uniqueNames(docs);

  return Workspace(
    name: j['name'] is String ? j['name'] as String : 'untitled',
    meta: meta,
    folders: folders,
    documents: docs,
    links: j['links'] is List ? List<Object?>.of(j['links'] as List) : [],
  );
}

/// ชื่อเอกสารไม่ว่างและไม่ซ้ำกันทั้งโปรเจกต์ (ไม่สนตัวพิมพ์) — ซ้ำ/ว่าง ต่อเลขท้าย
void _uniqueNames(List<ProjectDocument> docs) {
  final used = <String>{};
  for (final d in docs) {
    var base = cleanDiagramName(d.name);
    if (base.isEmpty) {
      base = switch (d.type) {
        DocType.er => 'ER',
        DocType.dfd => 'DFD',
        DocType.flowchart => 'Flowchart',
        null => 'Document',
      };
    }
    var name = base;
    for (var n = 2; used.contains(name.toLowerCase()); n++) {
      name = '$base $n';
    }
    used.add(name.toLowerCase());
    d.name = name;
  }
}

/// ที่เก็บข้อมูลที่ผูกตารางแต่ไม่ได้ระบุเอกสาร ER: ถ้าโปรเจกต์มี ER เอกสารเดียว ถือว่าเป็นของเอกสารนั้น
void _resolveTableDocs(Workspace w) {
  final ers = w.documentsOf(DocType.er).toList();
  if (ers.length != 1) return;
  for (final d in w.documents) {
    for (final n in d.dfd?.nodes ?? const <DfdNode>[]) {
      if (n.kind == DfdKind.store && n.tableId != null && n.tableDocId == null) n.tableDocId = ers.single.id;
    }
  }
}
