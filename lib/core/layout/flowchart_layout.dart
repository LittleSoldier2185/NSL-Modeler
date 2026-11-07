import '../models/flowchart_model.dart';
import 'layered_layout.dart';

/// ระยะห่างระหว่างชั้น / ระหว่างสัญลักษณ์ในชั้นเดียวกัน ตอนจัดวาง Flowchart อัตโนมัติ
const double kFcLayerGap = 60;
const double kFcRowGap = 50;

/// วิธีจัดวางอัตโนมัติของ Flowchart
enum FcLayoutKind {
  /// เป็นชั้นจากบนลงล่างตามทิศเส้น (ค่าเริ่มต้น)
  topDown,

  /// เป็นชั้นจากซ้ายไปขวา
  leftRight,
}

/// ตำแหน่งมุมซ้ายบนใหม่ของสัญลักษณ์ขั้นตอนทุกตัว (โน้ตไม่ถูกย้าย) — ไม่แก้แผนภาพ ; ผลลัพธ์คงที่
Map<String, ({double x, double y})> fcAutoLayout(FlowchartDiagram d, {FcLayoutKind kind = FcLayoutKind.topDown}) {
  final boxes = [
    for (final n in d.nodes)
      if (!fcIsAnnotation(n.shape)) LayoutBox(n.id, n.x, n.y, n.w, n.h),
  ];
  final ids = {for (final b in boxes) b.id};
  final edges = [
    for (final e in d.edges)
      if (ids.contains(e.fromId) && ids.contains(e.toId)) (e.fromId, e.toId),
  ];
  return layeredLayout(
    boxes,
    edges,
    horizontal: kind == FcLayoutKind.leftRight,
    layerGap: kind == FcLayoutKind.leftRight ? kFcLayerGap + 30 : kFcLayerGap,
    rowGap: kFcRowGap,
  );
}
