import '../models/dfd_model.dart';
import 'layered_layout.dart';

/// ระยะห่างระหว่างชั้น (แนวนอน) และระหว่างวัตถุในชั้นเดียวกัน (แนวตั้ง) ตอนจัดวางอัตโนมัติ
const double kDfdLayerGap = 140;
const double kDfdRowGap = 50;

/// จัดวาง DFD เป็นชั้นซ้าย→ขวาตามทิศทางข้อมูล คืนตำแหน่งมุมซ้ายบนใหม่ของทุกวัตถุ (ไม่แก้แผนภาพ)
///
/// - ชั้น = ระยะทางยาวสุดจากวัตถุต้นทาง (ไม่มีข้อมูลเข้า) ; เส้นที่วนกลับ (ทำให้เกิดวงจร) ไม่นับ
/// - ลำดับในชั้นเรียงตามค่าเฉลี่ยตำแหน่งของเพื่อนบ้าน (barycenter) เพื่อลดเส้นตัดกัน
/// - ผลลัพธ์ถูกเลื่อนให้มุมซ้ายบนของทั้งชุดอยู่ที่เดิม และเหมือนเดิมทุกครั้งที่เรียก (deterministic)
Map<String, ({double x, double y})> dfdAutoLayout(DfdDiagram d) => layeredLayout(
      [for (final n in d.nodes) LayoutBox(n.id, n.x, n.y, n.w, n.h)],
      [for (final f in d.flows) (f.fromId, f.toId)],
      horizontal: true,
      layerGap: kDfdLayerGap,
      rowGap: kDfdRowGap,
    );
