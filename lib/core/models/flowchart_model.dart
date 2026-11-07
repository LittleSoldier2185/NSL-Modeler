import 'dart:math' as math;

import 'color_utils.dart';
import 'workspace.dart';

/// รูปทรงของสัญลักษณ์ใน Flowchart
enum FcShape {
  /// เริ่มต้น (terminator รูปแคปซูล)
  start,

  /// สิ้นสุด (terminator รูปแคปซูล)
  end,

  /// กระบวนการ (สี่เหลี่ยม)
  process,

  /// การตัดสินใจ (ข้าวหลามตัด)
  decision,

  /// รับ/แสดงข้อมูล (สี่เหลี่ยมด้านขนาน)
  io,

  /// โปรแกรมย่อย / predefined process (สี่เหลี่ยมมีเส้นตั้งสองข้าง)
  subroutine,

  /// จุดต่อ (วงกลมเล็ก)
  connector,

  /// โน้ต (กระดาษพับมุม) — เป็นคำอธิบาย ไม่นับในกฎการไหล
  note,

  /// สี่เหลี่ยมมุมมน
  rounded,

  /// วงรี
  ellipse,
}

/// สัญลักษณ์ที่เป็นคำอธิบาย ไม่ใช่ขั้นตอน (ข้ามในกฎการไหลและการจัดวางอัตโนมัติ)
bool fcIsAnnotation(FcShape s) => s == FcShape.note;

/// ขนาดเริ่มต้นของแต่ละรูปทรง
(double, double) fcDefaultSize(FcShape s) => switch (s) {
      FcShape.start || FcShape.end => (140, 50),
      FcShape.process || FcShape.rounded || FcShape.io || FcShape.subroutine => (160, 64),
      FcShape.decision => (150, 90),
      FcShape.connector => (44, 44),
      FcShape.note => (170, 80),
      FcShape.ellipse => (130, 76),
    };

/// สีประจำรูปทรง (ใช้เมื่อไม่ได้กำหนดสีเส้นเอง) — ใช้ร่วมกันทั้งบนจอ PNG และ SVG
const Map<FcShape, int> kFcShapeColors = {
  FcShape.start: 0xFF16A34A,
  FcShape.end: 0xFFDC2626,
  FcShape.process: 0xFF2563EB,
  FcShape.decision: 0xFFD97706,
  FcShape.io: 0xFF0D9488,
  FcShape.subroutine: 0xFF7C3AED,
  FcShape.connector: 0xFF475569,
  FcShape.note: 0xFFCA8A04,
  FcShape.rounded: 0xFF4F46E5,
  FcShape.ellipse: 0xFFDB2777,
};

const double kFcMinSide = 24;
const double kFcMaxSide = 1200;

/// หัวลูกศรที่ปลายเส้น
enum FcArrow { none, arrow, open }

/// ลักษณะเส้น
enum FcDash { solid, dashed, dotted }

/// แนวข้อความ
enum FcAlign { left, center, right }

class FcNode {
  FcNode({
    required this.id,
    required this.shape,
    this.text = '',
    this.x = 0,
    this.y = 0,
    double? w,
    double? h,
    this.fill,
    this.stroke,
    this.textColor,
    this.fontSize = 13,
    this.bold = false,
    this.italic = false,
    this.align = FcAlign.center,
    this.dash = FcDash.solid,
  })  : w = w ?? fcDefaultSize(shape).$1,
        h = h ?? fcDefaultSize(shape).$2;

  final String id;
  FcShape shape;

  /// ข้อความในสัญลักษณ์ (หลายบรรทัดได้)
  String text;
  double x, y, w, h;

  /// สีพื้น/สีเส้นขอบ/สีตัวอักษร (ARGB) — null = ค่าเริ่มต้นตามชนิดและธีม
  int? fill, stroke, textColor;
  double fontSize;
  bool bold, italic;
  FcAlign align;

  /// เส้นขอบ
  FcDash dash;

  double get cx => x + w / 2;
  double get cy => y + h / 2;
  double get right => x + w;
  double get bottom => y + h;

  Map<String, dynamic> toJson() => {
        'id': id,
        'shape': shape.name,
        'text': text,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        if (fill != null) 'fill': fill,
        if (stroke != null) 'stroke': stroke,
        if (textColor != null) 'textColor': textColor,
        if (fontSize != 13) 'fontSize': fontSize,
        if (bold) 'bold': true,
        if (italic) 'italic': true,
        if (align != FcAlign.center) 'align': align.name,
        if (dash != FcDash.solid) 'dash': dash.name,
      };

  /// ค่าผิดปกติ = null (ข้ามสัญลักษณ์นั้น) หรือใช้ค่าปลอดภัย
  static FcNode? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final shape = FcShape.values.asNameMap()[j['shape']];
    if (id is! String || id.isEmpty || shape == null) return null;
    double num0(Object? v, double fb) => v is num && v.isFinite ? v.toDouble() : fb;
    final d = fcDefaultSize(shape);
    double side(Object? v, double fb) {
      final n = num0(v, fb);
      return n < kFcMinSide ? fb : math.min(n, kFcMaxSide);
    }

    final fs = num0(j['fontSize'], 13);
    return FcNode(
      id: id,
      shape: shape,
      text: j['text'] is String ? j['text'] as String : '',
      x: num0(j['x'], 0),
      y: num0(j['y'], 0),
      w: side(j['w'], d.$1),
      h: side(j['h'], d.$2),
      fill: parseArgb(j['fill']),
      stroke: parseArgb(j['stroke']),
      textColor: parseArgb(j['textColor']),
      fontSize: fs < 6 || fs > 96 ? 13 : fs,
      bold: j['bold'] == true,
      italic: j['italic'] == true,
      align: FcAlign.values.asNameMap()[j['align']] ?? FcAlign.center,
      dash: FcDash.values.asNameMap()[j['dash']] ?? FcDash.solid,
    );
  }
}

class FcEdge {
  FcEdge({
    required this.id,
    required this.fromId,
    required this.toId,
    this.label = '',
    this.color,
    this.dash = FcDash.solid,
    this.width = 1.8,
    this.startArrow = FcArrow.none,
    this.endArrow = FcArrow.arrow,
  });

  final String id;
  String fromId;
  String toId;
  String label;
  int? color;
  FcDash dash;
  double width;
  FcArrow startArrow, endArrow;

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': fromId,
        'to': toId,
        'label': label,
        if (color != null) 'color': color,
        if (dash != FcDash.solid) 'dash': dash.name,
        if (width != 1.8) 'width': width,
        if (startArrow != FcArrow.none) 'startArrow': startArrow.name,
        if (endArrow != FcArrow.arrow) 'endArrow': endArrow.name,
      };

  static FcEdge? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], from = j['from'], to = j['to'];
    if (id is! String || id.isEmpty || from is! String || to is! String) return null;
    final w = j['width'];
    return FcEdge(
      id: id,
      fromId: from,
      toId: to,
      label: j['label'] is String ? j['label'] as String : '',
      color: parseArgb(j['color']),
      dash: FcDash.values.asNameMap()[j['dash']] ?? FcDash.solid,
      width: w is num && w.isFinite && w >= 0.5 && w <= 12 ? w.toDouble() : 1.8,
      startArrow: FcArrow.values.asNameMap()[j['startArrow']] ?? FcArrow.none,
      endArrow: FcArrow.values.asNameMap()[j['endArrow']] ?? FcArrow.arrow,
    );
  }
}

/// เนื้อหาของเอกสาร Flowchart หนึ่งชิ้น (ลำดับใน [nodes] = ลำดับการซ้อน ท้ายรายการอยู่บนสุด)
class FlowchartDiagram implements DocContent {
  FlowchartDiagram({List<FcNode>? nodes, List<FcEdge>? edges})
      : nodes = nodes ?? [],
        edges = edges ?? [];

  final List<FcNode> nodes;
  final List<FcEdge> edges;

  FcNode? nodeById(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  FcEdge? edgeById(String id) {
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

  /// ซ่อมข้อมูลผิดปกติ: ข้ามสัญลักษณ์ที่อ่านไม่ได้/id ซ้ำ, ตัดเส้นที่ชี้ไปสัญลักษณ์ที่ไม่มีหรือ id ซ้ำ
  /// (เส้นวนเข้าตัวเองเก็บไว้ — ตัวตรวจจะแจ้งเตือน)
  factory FlowchartDiagram.fromJson(Object? j) {
    if (j is! Map) return FlowchartDiagram();
    final ids = <String>{};
    final nodes = [
      for (final e in (j['nodes'] is List ? j['nodes'] as List : const []))
        if (FcNode.tryFromJson(e) case final n? when ids.add(n.id)) n,
    ];
    final eids = <String>{};
    final edges = [
      for (final e in (j['edges'] is List ? j['edges'] as List : const []))
        if (FcEdge.tryFromJson(e) case final f? when ids.contains(f.fromId) && ids.contains(f.toId) && eids.add(f.id)) f,
    ];
    return FlowchartDiagram(nodes: nodes, edges: edges);
  }
}
