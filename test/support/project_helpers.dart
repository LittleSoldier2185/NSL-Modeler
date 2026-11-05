import 'package:nsl_dev/core/models/dfd_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/workspace.dart';
import 'package:nsl_dev/core/storage/project_file.dart';
import 'package:nsl_dev/state/project_controller.dart';

/// เขียน [p] เป็นไฟล์ (v3, ER เอกสารเดียว) แล้วอ่านกลับ — คืนเนื้อหา ER ที่อ่านได้
Project roundTripEr(Project p) => erOf(ProjectFile.decode(ProjectFile.encode(Workspace.single(p))));

/// เขียน workspace เป็นไฟล์แล้วอ่านกลับ
Workspace roundTrip(Workspace w) => ProjectFile.decode(ProjectFile.encode(w));

/// เนื้อหา ER แรกของ [w]
Project erOf(Workspace w) => w.firstEr!.er!;

/// เนื้อหา DFD ของเอกสาร [id] ใน [w] (ต้องมีอยู่)
DfdDiagram dfdIn(Workspace w, String id) => w.documentById(id)!.dfd!;

/// แทนเนื้อหาของเอกสาร DFD [id] ในโปรเจกต์ที่ controller ถืออยู่ (เตรียมข้อมูลเทสต์ ไม่เข้าประวัติ undo)
void setDfd(ProjectController c, String id, DfdDiagram d) {
  final doc = c.documentById(id)!;
  assert(doc.type == DocType.dfd);
  doc.content = d;
}
