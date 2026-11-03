import 'dart:math' as math;

import '../layout/diagram_geometry.dart';
import '../models/group_model.dart';
import '../models/project.dart';

/// ขอบเผื่อรอบตารางเมื่อต้องหดกรอบกลุ่มให้พอดีกับตารางที่เลือก
const double kCropGroupPad = 24;

/// โปรเจกต์ย่อยสำหรับ export "เฉพาะที่เลือก": ตารางที่เลือก + เส้น FK ระหว่างกัน + กรอบกลุ่มที่เกี่ยวข้อง
///
/// - กลุ่มที่มีตารางที่เลือกอยู่ข้างในจะติดไปด้วย (ชื่อและสีเดิม)
/// - ถ้าเลือกครบทุกตารางในกลุ่ม กรอบเท่าเดิม; ถ้าเลือกแค่บางตัว กรอบหดให้พอดีกับตารางที่เลือก (ไม่เหลือที่ว่างของตารางที่ไม่ได้เลือก)
/// - [groupId] = กลุ่มที่ถูกเลือกอยู่ ติดไปด้วยเสมอ (กลุ่มว่างก็ได้)
/// โน้ตไม่ติดไป
Project cropToSelection(Project p, Set<String> tableIds, {String? groupId, Set<String> groupIds = const {}}) {
  final tables = [for (final t in p.tables) if (tableIds.contains(t.id)) t];
  final groups = <GroupModel>[];
  for (final g in p.groups) {
    final members = groupMembers(p, g).tables.where(tableIds.contains).toList();
    final all = groupMembers(p, g).tables;
    final forced = g.id == groupId || groupIds.contains(g.id);
    if (members.isEmpty && !forced) continue;
    var x = g.x, y = g.y, w = g.width, h = g.height;
    if (members.isNotEmpty && members.length < all.length) {
      var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
      for (final id in members) {
        final tb = p.tableById(id)!;
        l = math.min(l, tb.x);
        t = math.min(t, tb.y);
        r = math.max(r, tb.x + tb.width);
        b = math.max(b, tb.y + tableHeight(tb));
      }
      x = l - kCropGroupPad;
      y = t - kCropGroupPad - kGroupHeader;
      w = math.max(kGroupMinWidth, r - l + 2 * kCropGroupPad);
      h = math.max(kGroupMinHeight, b - t + 2 * kCropGroupPad + kGroupHeader);
    }
    groups.add(GroupModel(
      id: g.id,
      name: g.name,
      x: x,
      y: y,
      width: w,
      height: h,
      colorIndex: g.colorIndex,
      customColor: g.customColor,
    ));
  }
  return Project(
    name: p.name,
    dialect: p.dialect,
    lineColor: p.lineColor,
    tables: tables,
    relations: [
      for (final r in p.relations)
        if (tableIds.contains(r.fromTableId) && tableIds.contains(r.toTableId)) r
    ],
    groups: groups,
  );
}
