import 'dfd_model.dart';
import 'diagram.dart';
import 'project.dart';

/// ชนิดเอกสารที่โปรแกรมรู้จัก (ชนิดอื่นจากไฟล์รุ่นใหม่กว่าเก็บเป็น [RawDocContent] และเขียนกลับไม่เปลี่ยน)
enum DocType {
  /// แผนภาพ ER — เนื้อหาคือ [Project]
  er,

  /// Data Flow Diagram — เนื้อหาคือ [DfdDiagram]
  dfd,
}

/// เนื้อหาของเอกสารหนึ่งชิ้น — เขียนเป็นค่า `content` ของเอกสารในไฟล์ v3
abstract interface class DocContent {
  Object? toContentJson();
}

/// เนื้อหาของเอกสารชนิดที่ไม่รู้จัก: เก็บค่าดิบไว้แล้วเขียนกลับเหมือนเดิมทุกประการ
class RawDocContent implements DocContent {
  RawDocContent(this.value);

  final Object? value;

  @override
  Object? toContentJson() => value;
}

/// โฟลเดอร์จัดกลุ่มเอกสาร ([parentId] null = อยู่ที่ราก)
class DocFolder {
  DocFolder({required this.id, required this.name, this.parentId});

  final String id;
  String name;
  String? parentId;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'parent': parentId};
}

/// ข้อมูลประกอบของโปรเจกต์ ([extra] = คีย์ที่ไม่รู้จัก เขียนกลับเหมือนเดิม)
class WorkspaceMeta {
  WorkspaceMeta({this.description = '', this.createdAt, Map<String, dynamic>? extra}) : extra = extra ?? {};

  String description;

  /// เวลาสร้าง (ISO-8601) — null = ไม่ทราบ (ไฟล์เก่า)
  String? createdAt;
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() => {
        'description': description,
        if (createdAt != null) 'createdAt': createdAt,
        ...extra,
      };
}

/// เอกสารหนึ่งชิ้นในโปรเจกต์ (แผนภาพ ER, DFD, ...)
class ProjectDocument {
  ProjectDocument({
    required this.id,
    required this.typeName,
    required this.name,
    required this.content,
    this.folderId,
    this.typeVersion = 1,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  ProjectDocument.er({required String id, required String name, required Project content, String? folderId})
      : this(id: id, typeName: DocType.er.name, name: name, content: content, folderId: folderId);

  ProjectDocument.dfd({required String id, required String name, required DfdDiagram content, String? folderId})
      : this(id: id, typeName: DocType.dfd.name, name: name, content: content, folderId: folderId);

  final String id;

  /// ชื่อชนิดตามที่เขียนในไฟล์ (คงไว้แม้ไม่รู้จัก)
  final String typeName;
  String name;
  String? folderId;
  int typeVersion;
  DocContent content;

  /// คีย์อื่นของเอกสารที่ไม่รู้จัก (เขียนกลับเหมือนเดิม)
  final Map<String, dynamic> extra;

  /// ชนิดที่รู้จัก — null = ชนิดที่โปรแกรมรุ่นนี้ไม่รู้จัก
  DocType? get type => content is RawDocContent ? null : DocType.values.asNameMap()[typeName];

  /// เนื้อหา ER (null ถ้าไม่ใช่เอกสาร ER)
  Project? get er => content is Project ? content as Project : null;

  /// เนื้อหา DFD (null ถ้าไม่ใช่เอกสาร DFD)
  DfdDiagram? get dfd => content is DfdDiagram ? content as DfdDiagram : null;
}

/// ทั้งโปรเจกต์ (ไฟล์ `.nsld` v3): ชื่อ ข้อมูลประกอบ โฟลเดอร์ เอกสาร และลิงก์ระหว่างเอกสาร
class Workspace {
  Workspace({
    this.name = 'untitled',
    WorkspaceMeta? meta,
    List<DocFolder>? folders,
    List<ProjectDocument>? documents,
    List<Object?>? links,
  })  : meta = meta ?? WorkspaceMeta(),
        folders = folders ?? [],
        documents = documents ?? [],
        links = links ?? [];

  String name;
  final WorkspaceMeta meta;
  final List<DocFolder> folders;
  final List<ProjectDocument> documents;

  /// ลิงก์ระหว่างเอกสาร — ตอนนี้อ่านและเขียนกลับตามเดิม (ยังไม่ได้ใช้งาน)
  final List<Object?> links;

  ProjectDocument? documentById(String id) {
    for (final d in documents) {
      if (d.id == id) return d;
    }
    return null;
  }

  DocFolder? folderById(String id) {
    for (final f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  Iterable<ProjectDocument> documentsOf(DocType type) => documents.where((d) => d.type == type);

  /// ชื่อเอกสารที่ยังไม่มีใครใช้ทั้งโปรเจกต์ ([base], [base] 2, ...) ไม่สนตัวพิมพ์
  String uniqueDocumentName(String base, {String? except}) {
    final used = {for (final d in documents) if (d.id != except) d.name.toLowerCase()};
    var name = base;
    for (var n = 2; used.contains(name.toLowerCase()); n++) {
      name = '$base $n';
    }
    return name;
  }

  /// เอกสาร ER แรกตามลำดับ (null = ไม่มี)
  ProjectDocument? get firstEr => documentsOf(DocType.er).firstOrNull;

  /// จำนวนตาราง/ความสัมพันธ์รวมของทุกเอกสาร ER
  int get tableCount => documentsOf(DocType.er).fold(0, (s, d) => s + d.er!.tables.length);
  int get relationCount => documentsOf(DocType.er).fold(0, (s, d) => s + d.er!.relations.length);

  /// โปรเจกต์ใหม่ที่มีเอกสาร ER เอกสารเดียว
  factory Workspace.single(Project er, {String docName = 'ER'}) => Workspace(
        name: er.name,
        documents: [ProjectDocument.er(id: kErDiagramId, name: docName, content: er)],
      );
}
