import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/db/db_session.dart';
import '../core/db/mysql_connector.dart';
import '../core/db/mysql_reader.dart';
import '../core/db/saved_connections.dart';
import '../core/db/sqlite_connector.dart';
import '../core/l10n/l10n.dart';
import '../core/models/enums.dart';
import 'theme.dart';
import 'widgets.dart' show Dropdown;

enum DbAction { importAsDiagram, compare, browse }


/// ผลของกล่องเชื่อมต่อ: โครงสร้างที่อ่านมาได้ + สิ่งที่ผู้ใช้เลือกจะทำต่อ
class DbConnectOutcome {
  const DbConnectOutcome(this.action, this.read, this.label, {this.sqlitePath, this.config, this.kind = DbKind.mysql});
  final DbAction action;

  /// ข้อมูลเชื่อมต่อ (ใช้เปิดดูข้อมูล) — รหัสผ่านอยู่ในหน่วยความจำเท่านั้น
  final DbConfig? config;
  final DbKind kind;

  /// ที่อยู่ไฟล์ถ้าเป็น SQLite (ใช้เสนอรัน migration กับไฟล์นั้น)
  final String? sqlitePath;
  /// โครงสร้างที่อ่านมา ; null เมื่อเลือก "เปิดดูข้อมูล" (ไม่ได้อ่านโครงสร้างมานำเข้า)
  final DbReadResult? read;

  /// ข้อความอธิบายแหล่งที่มา (ไม่มีรหัสผ่าน) เช่น root@localhost:3306/shop
  final String label;
}

/// เชื่อมต่อฐานข้อมูล MySQL / MariaDB หรือเปิดไฟล์ SQLite แบบอ่านอย่างเดียว แล้วอ่านโครงสร้างตาราง
/// ไม่เขียนอะไรลงฐานข้อมูลเลย รหัสผ่านไม่ถูกบันทึกที่ใด
class DbConnectDialog extends StatefulWidget {
  const DbConnectDialog({super.key, required this.projectDialect});

  /// dialect ของโปรเจกต์ที่เปิดอยู่ — เปรียบเทียบ (migration) ได้เมื่อ dialect ตรงกับชนิดฐานข้อมูลที่เลือก
  final Dialect projectDialect;

  /// ตัวเชื่อมต่อ (เปลี่ยนได้ในเทสต์)
  static DbConnector connector = const MysqlConnector();
  static DbConnector sqliteConnector = const SqliteConnector();

  /// ที่เก็บการเชื่อมต่อที่บันทึกไว้ (null = ปิดฟีเจอร์บันทึก)
  static SavedConnectionStore? store;

  /// ชนิดที่เลือกครั้งก่อนในรอบการใช้งานนี้
  static DbKind lastKind = DbKind.mysql;

  /// ไฟล์ SQLite ที่เปิดครั้งก่อนในรอบการใช้งานนี้
  static String lastSqlitePath = '';

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
  late final _sqlitePath = TextEditingController(text: DbConnectDialog.lastSqlitePath);
  late bool _secure = DbConnectDialog.last.secure;
  late DbKind _kind = DbConnectDialog.lastKind;

  // ---- การเชื่อมต่อที่บันทึกไว้ ----
  late List<SavedConnection> _saved = DbConnectDialog.store?.load() ?? const [];
  String _picked = '';
  bool _save = false;
  bool _remember = false;
  final _saveName = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _status;

  @override
  void dispose() {
    for (final c in [_host, _port, _user, _db, _pass, _sqlitePath, _saveName]) {
      c.dispose();
    }
    super.dispose();
  }

  DbConfig? _config() {
    if (_kind == DbKind.sqlite) {
      final p = _sqlitePath.text.trim();
      if (p.isEmpty) {
        setState(() => _error = tr('กรอกที่อยู่ไฟล์ SQLite'));
        return null;
      }
      return DbConfig(host: '', port: 0, user: '', database: p);
    }
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
      s = await (_kind == DbKind.sqlite ? DbConnectDialog.sqliteConnector : DbConnectDialog.connector).connect(cfg);
      if (!readSchema) {
        if (mounted) setState(() => _status = tr('เชื่อมต่อสำเร็จ'));
        return null;
      }
      void progress(int done, int total) {
        if (mounted) setState(() => _status = tr('กำลังอ่านโครงสร้าง {0}/{1}', [done, total]));
      }

      if (_kind == DbKind.sqlite) {
        final base = cfg.database.split(RegExp(r'[\\/]')).last;
        final name = base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;
        return await readSqliteSchema(s, name: name, onProgress: progress);
      }
      return await readMysqlSchema(s, database: cfg.database, onProgress: progress);
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

  void _pick(String name) {
    setState(() {
      _picked = name;
      _error = null;
      _status = null;
      final c = _saved.where((e) => e.name == name).firstOrNull;
      if (c == null) return;
      _kind = c.kind;
      if (c.kind == DbKind.sqlite) {
        _sqlitePath.text = c.database;
      } else {
        _host.text = c.host;
        _port.text = '${c.port}';
        _user.text = c.user;
        _db.text = c.database;
        _secure = c.secure;
        final pw = DbConnectDialog.store?.passwordOf(c);
        _pass.text = pw ?? '';
        _remember = pw != null;
      }
      _save = true;
      _saveName.text = c.name;
    });
  }

  void _deleteSaved() {
    final s = DbConnectDialog.store;
    if (s == null || _picked.isEmpty) return;
    s.remove(_picked);
    setState(() {
      _saved = s.load();
      _picked = '';
      _save = false;
      _remember = false;
      _pass.clear();
    });
  }

  /// บันทึกการเชื่อมต่อที่เชื่อมสำเร็จ (ถ้าผู้ใช้ติ๊ก) : รหัสผ่านเก็บเฉพาะเมื่อติ๊ก "จำรหัสผ่าน" และเข้ารหัสได้
  void _saveConnection(DbConfig cfg) {
    final s = DbConnectDialog.store;
    if (s == null || !_save) return;
    final name = _saveName.text.trim().isEmpty ? (_kind == DbKind.sqlite ? cfg.database : cfg.label) : _saveName.text.trim();
    try {
      s.upsert(
        SavedConnection(
          name: name,
          kind: _kind,
          host: cfg.host,
          port: cfg.port,
          user: cfg.user,
          database: cfg.database,
          secure: cfg.secure,
        ),
        password: _kind == DbKind.mysql && _remember ? cfg.password : null,
      );
    } catch (_) {
      // บันทึกรายการไม่ได้ก็เชื่อมต่อต่อไปได้ตามปกติ
    }
  }

  Future<void> _go(DbAction action) async {
    final cfg = _config();
    if (cfg == null) return;
    if (action == DbAction.browse) {
      // ทดลองเชื่อมต่อก่อน : ล้มเหลวจะแสดงข้อผิดพลาดในกล่องนี้ ไม่ปิดกล่อง
      await _run(cfg, readSchema: false);
      if (_error != null || !mounted) return;
      _saveConnection(cfg);
      DbConnectDialog.lastKind = _kind;
      if (_kind == DbKind.sqlite) {
        DbConnectDialog.lastSqlitePath = cfg.database;
      } else {
        DbConnectDialog.last = cfg.copyWith(password: '');
      }
      final label = _kind == DbKind.sqlite ? cfg.database : cfg.label;
      Navigator.pop(context, DbConnectOutcome(action, null, label, config: cfg, kind: _kind, sqlitePath: _kind == DbKind.sqlite ? cfg.database : null));
      return;
    }
    final r = await _run(cfg, readSchema: true);
    if (r == null || !mounted) return;
    _saveConnection(cfg);
    DbConnectDialog.lastKind = _kind;
    if (_kind == DbKind.sqlite) {
      DbConnectDialog.lastSqlitePath = cfg.database;
    } else {
      DbConnectDialog.last = cfg.copyWith(password: ''); // จำเฉพาะค่าที่ไม่ลับ
    }
    _pass.clear();
    Navigator.pop(context, DbConnectOutcome(action, r, _kind == DbKind.sqlite ? cfg.database : cfg.label, sqlitePath: _kind == DbKind.sqlite ? cfg.database : null));
  }

  Future<void> _browse() async {
    final f = await FilePicker.pickFile(
      dialogTitle: tr('เลือกไฟล์ฐานข้อมูล SQLite'),
      type: FileType.custom,
      allowedExtensions: const ['db', 'sqlite', 'sqlite3', 'db3'],
    );
    final p = f?.path;
    if (p != null && mounted) setState(() => _sqlitePath.text = p);
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
    final sqlite = _kind == DbKind.sqlite;
    final canCompare = widget.projectDialect == (sqlite ? Dialect.sqlite : Dialect.mysql);
    return AlertDialog(
      title: Text(tr('เชื่อมต่อฐานข้อมูล')),
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
                    tr('อ่านโครงสร้างเท่านั้น ไม่แก้ไข/ลบอะไรในฐานข้อมูล · รหัสผ่านไม่ถูกบันทึก เว้นแต่คุณเลือกจำเอง (เข้ารหัสด้วย Windows)'),
                    style: TextStyle(fontSize: 12.5, color: C.primaryDark, height: 1.4),
                  ),
                ),
              ]),
            ),
            if (_saved.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: KeyedSubtree(
                    key: const ValueKey('db-saved'),
                    child: Dropdown<String>(
                      value: _saved.any((e) => e.name == _picked) ? _picked : '',
                      items: ['', ..._saved.map((e) => e.name)],
                      labelOf: (n) => n.isEmpty ? tr('— การเชื่อมต่อที่บันทึกไว้ —') : n,
                      onChanged: _busy ? (_) {} : _pick,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('db-saved-delete'),
                  tooltip: tr('ลบการเชื่อมต่อที่บันทึกไว้'),
                  onPressed: _busy || _picked.isEmpty ? null : _deleteSaved,
                  icon: Icon(Icons.delete_outline, color: _picked.isEmpty ? C.muted : C.danger, size: 20),
                ),
              ]),
            ],
            const SizedBox(height: 12),
            SegmentedButton<DbKind>(
              key: const ValueKey('db-kind'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: DbKind.mysql, label: Text('MySQL / MariaDB')),
                ButtonSegment(value: DbKind.sqlite, label: Text('SQLite')),
              ],
              selected: {_kind},
              onSelectionChanged: _busy ? null : (v) => setState(() {
                _kind = v.first;
                _error = null;
                _status = null;
              }),
            ),
            const SizedBox(height: 14),
            if (sqlite)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _field(tr('ที่อยู่ไฟล์ SQLite'), _sqlitePath, key: const ValueKey('db-file'))),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: OutlinedButton(
                    key: const ValueKey('db-browse'),
                    onPressed: _busy ? null : _browse,
                    child: Text(tr('เลือกไฟล์…')),
                  ),
                ),
              ])
            else ...[
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
            ],
            if (DbConnectDialog.store != null) ...[
              CheckboxListTile(
                key: const ValueKey('db-save'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _save,
                onChanged: _busy ? null : (v) => setState(() => _save = v ?? false),
                title: Text(tr('บันทึกการเชื่อมต่อนี้ไว้ใช้ครั้งหน้า'), style: const TextStyle(fontSize: 13)),
              ),
              if (_save) ...[
                _field(tr('ชื่อที่บันทึก'), _saveName, key: const ValueKey('db-save-name')),
                if (!sqlite && DbConnectDialog.store!.canRememberPassword)
                  CheckboxListTile(
                    key: const ValueKey('db-remember'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _remember,
                    onChanged: _busy ? null : (v) => setState(() => _remember = v ?? false),
                    title: Text(tr('จำรหัสผ่านด้วย (เข้ารหัสด้วยบัญชี Windows ของคุณ)'), style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ],
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
                sqlite
                    ? tr('เปรียบเทียบ (สร้าง migration) ใช้ได้เมื่อ dialect ของโปรเจกต์เป็น SQLite')
                    : tr('เปรียบเทียบ (สร้าง migration) ใช้ได้เมื่อ dialect ของโปรเจกต์เป็น MySQL / MariaDB'),
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
        OutlinedButton(
          key: const ValueKey('db-browse-data'),
          onPressed: _busy ? null : () => _go(DbAction.browse),
          child: Text(tr('เปิดดู/แก้ข้อมูล')),
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
