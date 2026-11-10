import 'dart:math' as math;

import '../layout/box_ops.dart';
import 'color_utils.dart';
import 'workspace.dart';

/// ชนิดของโหนดใน Screen Flow
enum SfKind {
  /// จุดเริ่ม (ผู้ใช้เข้าแอป)
  start,

  /// หน้าจอ (ผูกกับเอกสาร Wireframe ได้)
  screen,

  /// หน้าภายนอก / ป๊อปอัป (เช่น เว็บอื่น อีเมล กล่องโต้ตอบ)
  external,

  /// จุดจบ (ออกจากระบบ / จบงาน)
  end,
}

/// ขนาดเริ่มต้นของแต่ละชนิด
(double, double) sfDefaultSize(SfKind k) => switch (k) {
      SfKind.start || SfKind.end => (130, 46),
      SfKind.screen => (190, 160),
      SfKind.external => (170, 80),
    };

const double kSfMinSide = 30;
const double kSfMaxSide = 1600;

class SfNode implements EditableBox {
  SfNode({
    required this.id,
    required this.kind,
    this.title = '',
    this.x = 0,
    this.y = 0,
    double? w,
    double? h,
    this.wireframeId,
    this.color,
  })  : w = w ?? sfDefaultSize(kind).$1,
        h = h ?? sfDefaultSize(kind).$2;

  @override
  final String id;
  SfKind kind;
  String title;
  @override
  double x;
  @override
  double y;
  @override
  double w;
  @override
  double h;

  /// เอกสาร Wireframe ที่เป็นหน้าจอนี้ (null = ยังไม่ผูก)
  String? wireframeId;

  /// สีเส้นขอบ (ARGB) — null = ค่าเริ่มต้นตามชนิด
  int? color;

  double get cx => x + w / 2;
  double get cy => y + h / 2;
  double get right => x + w;
  double get bottom => y + h;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        if (wireframeId != null) 'wireframe': wireframeId,
        if (color != null) 'color': color,
      };

  static SfNode? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final kind = SfKind.values.asNameMap()[j['kind']];
    if (id is! String || id.isEmpty || kind == null) return null;
    double num0(Object? v, double fb) => v is num && v.isFinite ? v.toDouble() : fb;
    final d = sfDefaultSize(kind);
    double side(Object? v, double fb) {
      final n = num0(v, fb);
      return n < kSfMinSide ? fb : math.min(n, kSfMaxSide);
    }

    final wf = j['wireframe'];
    return SfNode(
      id: id,
      kind: kind,
      title: j['title'] is String ? j['title'] as String : '',
      x: num0(j['x'], 0),
      y: num0(j['y'], 0),
      w: side(j['w'], d.$1),
      h: side(j['h'], d.$2),
      wireframeId: wf is String && wf.isNotEmpty ? wf : null,
      color: parseArgb(j['color']),
    );
  }
}

/// การเปลี่ยนหน้า (navigation) จาก [fromId] ไป [toId] — [label] = สิ่งที่ผู้ใช้ทำ (เช่น "กด Login"), [condition] = เงื่อนไข
class SfEdge {
  SfEdge({required this.id, required this.fromId, required this.toId, this.label = '', this.condition = ''});

  final String id;
  String fromId;
  String toId;
  String label;
  String condition;

  /// ข้อความที่แสดงบนเส้น: "ป้าย [เงื่อนไข]"
  String get caption {
    final l = label.trim(), c = condition.trim();
    if (c.isEmpty) return l;
    return l.isEmpty ? '[$c]' : '$l [$c]';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': fromId,
        'to': toId,
        'label': label,
        if (condition.isNotEmpty) 'condition': condition,
      };

  static SfEdge? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], from = j['from'], to = j['to'];
    if (id is! String || id.isEmpty || from is! String || to is! String) return null;
    return SfEdge(
      id: id,
      fromId: from,
      toId: to,
      label: j['label'] is String ? j['label'] as String : '',
      condition: j['condition'] is String ? j['condition'] as String : '',
    );
  }
}

/// เนื้อหาของเอกสาร Screen Flow (แผนผังการเปลี่ยนหน้าจอ)
class ScreenFlowDiagram implements DocContent {
  ScreenFlowDiagram({List<SfNode>? nodes, List<SfEdge>? edges})
      : nodes = nodes ?? [],
        edges = edges ?? [];

  final List<SfNode> nodes;
  final List<SfEdge> edges;

  SfNode? nodeById(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  SfEdge? edgeById(String id) {
    for (final e in edges) {
      if (e.id == id) return e;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
      };

  @override
  Map<String, dynamic> toContentJson() => toJson();

  /// ซ่อมข้อมูลผิดปกติ: ข้ามโหนดที่อ่านไม่ได้/id ซ้ำ, ตัดเส้นที่ชี้ไปโหนดที่ไม่มี/id ซ้ำ
  factory ScreenFlowDiagram.fromJson(Object? j) {
    if (j is! Map) return ScreenFlowDiagram();
    final ids = <String>{};
    final nodes = [
      for (final e in (j['nodes'] is List ? j['nodes'] as List : const []))
        if (SfNode.tryFromJson(e) case final n? when ids.add(n.id)) n,
    ];
    final eids = <String>{};
    final edges = [
      for (final e in (j['edges'] is List ? j['edges'] as List : const []))
        if (SfEdge.tryFromJson(e) case final f? when ids.contains(f.fromId) && ids.contains(f.toId) && eids.add(f.id)) f,
    ];
    return ScreenFlowDiagram(nodes: nodes, edges: edges);
  }
}
