import 'dart:convert';
import 'dart:io';

import 'db_session.dart';
import 'secret_codec.dart';

/// การเชื่อมต่อที่ผู้ใช้เลือกบันทึกไว้ใช้ซ้ำ
/// รหัสผ่านไม่เคยอยู่ในไฟล์เป็นข้อความเปล่า : มีเฉพาะ [passwordEnc] ที่เข้ารหัสด้วย [SecretCodec] ของเครื่อง (ถ้าผู้ใช้เลือกจำ)
class SavedConnection {
  const SavedConnection({
    required this.name,
    this.kind = DbKind.mysql,
    this.host = 'localhost',
    this.port = 3306,
    this.user = '',
    this.database = '',
    this.secure = false,
    this.passwordEnc,
  });

  /// ชื่อที่ผู้ใช้ตั้ง (ไม่ซ้ำ ไม่สนตัวพิมพ์) ; ของ SQLite ที่อยู่ไฟล์เก็บใน [database]
  final String name;
  final DbKind kind;
  final String host;
  final int port;
  final String user;
  final String database;
  final bool secure;
  final String? passwordEnc;

  SavedConnection copyWith({String? name, String? passwordEnc, bool clearPassword = false}) => SavedConnection(
        name: name ?? this.name,
        kind: kind,
        host: host,
        port: port,
        user: user,
        database: database,
        secure: secure,
        passwordEnc: clearPassword ? null : (passwordEnc ?? this.passwordEnc),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind.name,
        if (kind == DbKind.mysql) ...{'host': host, 'port': port, 'user': user, 'secure': secure},
        'database': database,
        if (passwordEnc != null) 'pw': passwordEnc,
      };

  static SavedConnection? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final name = j['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final kind = DbKind.values.where((k) => k.name == j['kind']).firstOrNull ?? DbKind.mysql;
    final port = j['port'];
    return SavedConnection(
      name: name.trim(),
      kind: kind,
      host: j['host'] is String ? j['host'] as String : 'localhost',
      port: port is int && port >= 1 && port <= 65535 ? port : 3306,
      user: j['user'] is String ? j['user'] as String : '',
      database: j['database'] is String ? j['database'] as String : '',
      secure: j['secure'] == true,
      passwordEnc: j['pw'] is String && (j['pw'] as String).isNotEmpty ? j['pw'] as String : null,
    );
  }
}

/// ไฟล์รายการการเชื่อมต่อที่บันทึกไว้ (JSON) — ไฟล์เสีย/หาย = รายการว่าง ไม่ทำให้แอปล้ม ; เขียนผ่านไฟล์ชั่วคราวกันไฟล์พัง
class SavedConnectionStore {
  SavedConnectionStore(this.file, this.codec);
  final File file;
  final SecretCodec codec;

  /// เสนอ "จำรหัสผ่าน" ได้หรือไม่
  bool get canRememberPassword => codec.available;

  List<SavedConnection> load() {
    try {
      if (!file.existsSync()) return const [];
      final j = jsonDecode(file.readAsStringSync());
      if (j is! Map || j['connections'] is! List) return const [];
      final seen = <String>{};
      return [
        for (final e in (j['connections'] as List))
          if (SavedConnection.tryFromJson(e) case final c? when seen.add(c.name.toLowerCase())) c,
      ];
    } catch (_) {
      return const [];
    }
  }

  void _write(List<SavedConnection> list) {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(jsonEncode({'version': 1, 'connections': [for (final c in list) c.toJson()]}), flush: true);
    tmp.renameSync(file.path);
  }

  /// เพิ่ม/แทนที่ตามชื่อ ; [password] != null และเข้ารหัสได้ = เก็บแบบเข้ารหัส , ไม่เช่นนั้นไม่เก็บรหัสผ่าน (null = ล้างของเดิม)
  /// คืน true ถ้าเก็บรหัสผ่านด้วย
  bool upsert(SavedConnection c, {String? password}) {
    String? enc;
    if (password != null && password.isNotEmpty && codec.available) enc = codec.encrypt(password);
    final item = enc == null ? c.copyWith(clearPassword: true) : c.copyWith(passwordEnc: enc);
    final list = [for (final e in load()) if (e.name.toLowerCase() != c.name.toLowerCase()) e, item]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _write(list);
    return enc != null;
  }

  void remove(String name) {
    final list = [for (final e in load()) if (e.name.toLowerCase() != name.toLowerCase()) e];
    _write(list);
  }

  /// รหัสผ่านที่จำไว้ของ [c] (ถอดรหัส) ; ไม่มี/ถอดไม่ได้ = null
  String? passwordOf(SavedConnection c) {
    final enc = c.passwordEnc;
    return enc == null ? null : codec.decrypt(enc);
  }
}
