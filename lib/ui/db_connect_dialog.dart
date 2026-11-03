import 'package:flutter/material.dart';

import '../core/db/db_session.dart';
import '../core/db/mysql_connector.dart';
import '../core/db/mysql_reader.dart';
import '../core/l10n/l10n.dart';
import '../core/models/enums.dart';
import 'theme.dart';

enum DbAction { importAsDiagram, compare }

/// ผลของกล่องเชื่อมต่อ: โครงสร้างที่อ่านมาได้ + สิ่งที่ผู้ใช้เลือกจะทำต่อ
class DbConnectOutcome {
  const DbConnectOutcome(this.action, this.read, this.label);
  final DbAction action;
  final DbReadResult read;

  /// ข้อความอธิบายแหล่งที่มา (ไม่มีรหัสผ่าน) เช่น root@localhost:3306/shop
  final String label;
}

/// เชื่อมต่อฐานข้อมูล MySQL / MariaDB แบบอ่านอย่างเดียว แล้วอ่านโครงสร้างตาราง
/// ไม่เขียนอะไรลงฐานข้อมูลเลย รหัสผ่านไม่ถูกบันทึกที่ใด
class DbConnectDialog extends StatefulWidget {
  const DbConnectDialog({super.key, required this.projectDialect});

  /// dialect ของโปรเจกต์ที่เปิดอยู่ — เปรียบเทียบ (migration) ได้เมื่อเป็น MySQL เท่านั้น
  final Dialect projectDialect;

  /// ตัวเชื่อมต่อ (เปลี่ยนได้ในเทสต์)
  static DbConnector connector = const MysqlConnector();

  /// ค่าที่กรอกครั้งก่อนในรอบการใช้งานนี้ (ไม่รวมรหัสผ่าน)
  static DbConfig last = const DbConfig();

  @override
  State<DbConnectDialog> createState() => _DbConnectDialogState();
}

class _DbConnectDialogState extends State<DbConnectDialog> {
  late final _host = TextEditingController(text: DbConnectDialog.last.host);
  late final _port = TextEditingController(text: '${DbConnectDialog.last.port}');
  late final _user = TextEditingController(text: DbConnectDialog.last.user);
  late final _db = TextEditingController(text: DbConnectDialog.last.database);
  final _pass = TextEditingController();
  late bool _secure = DbConnectDialog.last.secure;

  bool _busy = false;
  String? _error;
  String? _status;

  @override
  void dispose() {
    for (final c in [_host, _port, _user, _db, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  DbConfig? _config() {
    final port = int.tryParse(_port.text.trim());
    if (_host.text.trim().isEmpty || port == null || port < 1 || port > 65535) {
      setState(() => _error = tr('กรอกชื่อเครื่องและพอร์ต (1-65535) ให้ถูกต้อง'));
      return null;
    }
    if (_db.text.trim().isEmpty) {
      setState(() => _error = tr('กรอกชื่อฐานข้อมูล'));
      return null;
    }
    return DbConfig(
      host: _host.text.trim(),
      port: port,
      user: _user.text.trim(),
      password: _pass.text,
      database: _db.text.trim(),
      secure: _secure,
    );
  }

  /// เชื่อมต่อ -> (อ่านโครงสร้าง) -> ปิดการเชื่อมต่อเสมอ; แสดงข้อผิดพลาดในกล่อง ไม่ปิดกล่อง
  Future<DbReadResult?> _run(DbConfig cfg, {required bool readSchema}) async {
    setState(() {
      _busy = true;
      _error = null;
      _status = tr('กำลังเชื่อมต่อ…');
    });
    DbSession? s;
    try {
      s = await DbConnectDialog.connector.connect(cfg);
      if (!readSchema) {
        if (mounted) setState(() => _status = tr('เชื่อมต่อสำเร็จ'));
        return null;
      }
      final r = await readMysqlSchema(s, database: cfg.database, onProgress: (done, total) {
        if (mounted) setState(() => _status = tr('กำลังอ่านโครงสร้าง {0}/{1}', [done, total]));
      });
      return r;
    } on DbException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = tr('เกิดข้อผิดพลาด: {0}', [e]));
    } finally {
      try {
        await s?.close();
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  Future<void> _test() async {
    final cfg = _config();
    if (cfg == null) return;
    await _run(cfg, readSchema: false);
  }

  Future<void> _go(DbAction action) async {
    final cfg = _config();
    if (cfg == null) return;
    final r = await _run(cfg, readSchema: true);
    if (r == null || !mounted) return;
    DbConnectDialog.last = cfg.copyWith(password: ''); // จำเฉพาะค่าที่ไม่ลับ
    _pass.clear();
    Navigator.pop(context, DbConnectOutcome(action, r, cfg.label));
  }

  Widget _field(String label, TextEditingController c, {Key? key, bool obscure = false, double? width, TextInputType? type}) {
    final f = TextField(
      key: key,
      controller: c,
      obscureText: obscure,
      enabled: !_busy,
      keyboardType: type,
      enableSuggestions: !obscure,
      autocorrect: false,
      decoration: InputDecoration(isDense: true, labelText: label),
    );
    return width == null ? f : SizedBox(width: width, child: f);
  }

  @override
  Widget build(BuildContext context) {
    final canCompare = widget.projectDialect == Dialect.mysql;
    return AlertDialog(
      title: Text(tr('เชื่อมต่อฐานข้อมูล MySQL / MariaDB')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: C.primaryTint, borderRadius: BorderRadius.circular(8)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: C.primaryDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('อ่านโครงสร้างเท่านั้น ไม่แก้ไข/ลบอะไรในฐานข้อมูล และไม่บันทึกรหัสผ่าน'),
                    style: TextStyle(fontSize: 12.5, color: C.primaryDark, height: 1.4),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _field(tr('ชื่อเครื่อง (Host)'), _host, key: const ValueKey('db-host'))),
              const SizedBox(width: 10),
              _field(tr('พอร์ต'), _port, key: const ValueKey('db-port'), width: 90, type: TextInputType.number),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _field(tr('ผู้ใช้'), _user, key: const ValueKey('db-user'))),
              const SizedBox(width: 10),
              Expanded(child: _field(tr('รหัสผ่าน'), _pass, key: const ValueKey('db-pass'), obscure: true)),
            ]),
            const SizedBox(height: 12),
            _field(tr('ชื่อฐานข้อมูล'), _db, key: const ValueKey('db-name')),
            CheckboxListTile(
              key: const ValueKey('db-secure'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _secure,
              onChanged: _busy ? null : (v) => setState(() => _secure = v ?? false),
              title: Text(tr('ใช้การเข้ารหัส SSL/TLS (เซิร์ฟเวอร์ต้องรองรับ)'), style: const TextStyle(fontSize: 13)),
            ),
            if (_busy || _status != null || _error != null) ...[
              const SizedBox(height: 6),
              if (_error != null)
                Container(
                  key: const ValueKey('db-error'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: C.dangerBg, borderRadius: BorderRadius.circular(8)),
                  child: Text(_error!, style: TextStyle(fontSize: 12.5, color: C.danger, height: 1.4)),
                )
              else
                Row(children: [
                  if (_busy) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  if (_busy) const SizedBox(width: 8),
                  Flexible(child: Text(_status ?? '', key: const ValueKey('db-status'), style: TextStyle(fontSize: 12.5, color: C.muted))),
                ]),
            ],
            if (!canCompare) ...[
              const SizedBox(height: 8),
              Text(
                tr('เปรียบเทียบ (สร้าง migration) ใช้ได้เมื่อ dialect ของโปรเจกต์เป็น MySQL / MariaDB'),
                style: TextStyle(fontSize: 12, color: C.muted),
              ),
            ],
          ]),
        ),
      ),
      actionsOverflowButtonSpacing: 6,
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
        TextButton(key: const ValueKey('db-test'), onPressed: _busy ? null : _test, child: Text(tr('ทดสอบการเชื่อมต่อ'))),
        OutlinedButton(
          key: const ValueKey('db-compare'),
          onPressed: _busy || !canCompare ? null : () => _go(DbAction.compare),
          child: Text(tr('เปรียบเทียบกับแผนภาพ')),
        ),
        FilledButton(
          key: const ValueKey('db-import'),
          onPressed: _busy ? null : () => _go(DbAction.importAsDiagram),
          child: Text(tr('นำเข้าเป็นแผนภาพ')),
        ),
      ],
    );
  }
}
