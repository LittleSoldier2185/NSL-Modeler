import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_modeler/core/diff/schema_diff.dart';
import 'package:nsl_modeler/core/models/enums.dart';

import 'migration_fixtures.dart';

void main() {
  test('SQLite → SQLite : VARCHAR(255) กับ TEXT คือชนิดเดียวกัน (SQLite เก็บเป็น TEXT) ไม่ใช่การเปลี่ยนชนิด', () {
    final a = base(Dialect.sqlite);
    final b = clone(a);
    cl(b, 'tu', 'u2')
      ..type = DataType.text
      ..length = null;
    cl(b, 'tu', 'u3').length = 500; // ความยาวไม่มีผลใน SQLite
    expect(diffProjects(a, b).isEmpty, true);
  });

  test('SQLite : เปลี่ยนชนิดจริง (INTEGER → TEXT) ยังถูกจับ', () {
    final a = base(Dialect.sqlite);
    final b = clone(a);
    cl(b, 'tu', 'u4').type = DataType.varchar;
    final d = diffProjects(a, b);
    expect(d.isEmpty, false);
    expect(d.modified.single.changedColumns.single.typeChanged, true);
  });

  test('MySQL : VARCHAR(255) → TEXT ยังถือว่าเปลี่ยนชนิด (พฤติกรรมเดิมไม่เปลี่ยน)', () {
    final a = base(Dialect.mysql);
    final b = clone(a);
    cl(b, 'tu', 'u2')
      ..type = DataType.text
      ..length = null;
    expect(diffProjects(a, b).modified.single.changedColumns.single.typeChanged, true);
  });

  test('ฝั่งหนึ่ง SQLite อีกฝั่ง MySQL (เปรียบเทียบข้าม dialect) : ใช้การเทียบเดิม', () {
    final a = base(Dialect.sqlite);
    final b = clone(base(Dialect.mysql));
    expect(diffProjects(a, b).isEmpty, true); // ชนิดเดียวกันตามนิยาม ไม่ได้ถูกบังคับเป็น TEXT
  });
}
