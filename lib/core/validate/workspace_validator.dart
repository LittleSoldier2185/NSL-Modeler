import '../models/workspace.dart';
import 'dfd_validator.dart';
import 'flowchart_validator.dart';
import 'issue.dart';
import 'screenflow_validator.dart';
import 'wireframe_validator.dart';
import 'validator.dart';

/// ปัญหาหนึ่งรายการที่รู้ว่าอยู่ในเอกสารไหน
class WorkspaceIssue {
  const WorkspaceIssue({required this.docId, required this.docName, required this.docType, required this.issue});

  final String docId;
  final String docName;
  final DocType docType;
  final Issue issue;
}

/// ตรวจทุกเอกสารในโปรเจกต์ (ER / DFD / Flowchart / Wireframe / Screen Flow ทุกอัน) ตามลำดับเอกสารในไฟล์ ; ชนิดที่ไม่รู้จักข้ามไป
List<WorkspaceIssue> validateWorkspace(Workspace w) {
  final out = <WorkspaceIssue>[];
  for (final doc in w.documents) {
    final type = doc.type;
    final List<Issue> issues;
    switch (type) {
      case DocType.er:
        issues = validateProject(doc.er!);
      case DocType.dfd:
        issues = validateDfd(doc.dfd!, workspace: w, diagramId: doc.id);
      case DocType.flowchart:
        issues = validateFlowchart(doc.flowchart!);
      case DocType.wireframe:
        issues = validateWireframe(doc.wireframe!, workspace: w);
      case DocType.screenflow:
        issues = validateScreenFlow(doc.screenflow!, workspace: w);
      case null:
        continue;
    }
    for (final i in issues) {
      out.add(WorkspaceIssue(docId: doc.id, docName: doc.name, docType: type!, issue: i));
    }
  }
  return out;
}

/// จำนวนปัญหาแยกตามระดับ (ไม่นับ info ในช่อง warnings)
({int errors, int warnings, int infos}) countIssues(Iterable<Issue> issues) {
  var e = 0, w = 0, i = 0;
  for (final x in issues) {
    switch (x.severity) {
      case Severity.error:
        e++;
      case Severity.warning:
        w++;
      case Severity.info:
        i++;
    }
  }
  return (errors: e, warnings: w, infos: i);
}
