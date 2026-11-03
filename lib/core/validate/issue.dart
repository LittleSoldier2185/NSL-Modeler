enum Severity {
  /// SQL ที่ได้จะ import ไม่ผ่าน หรือความหมายผิด
  error,

  /// import ผ่านแต่น่าจะไม่ใช่สิ่งที่ตั้งใจ
  warning,

  /// คำแนะนำ
  info,
}

class Issue {
  const Issue({
    required this.severity,
    required this.code,
    required this.title,
    required this.message,
    this.tableId,
    this.columnId,
    this.relationId,
  });

  final Severity severity;

  /// รหัสคงที่ ใช้ในเทสต์และการกรอง เช่น `no_pk`, `fk_type_mismatch`
  final String code;
  final String title;
  final String message;
  final String? tableId;
  final String? columnId;
  final String? relationId;

  @override
  String toString() => '${severity.name}:$code($message)';
}
