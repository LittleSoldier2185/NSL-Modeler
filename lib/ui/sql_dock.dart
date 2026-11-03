import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/ddl/ddl_generator.dart';
import '../core/models/enums.dart';
import '../core/validate/issue.dart';
import '../state/project_controller.dart';
import 'canvas/canvas_controller.dart';
import 'issue_widgets.dart';
import 'sql_view.dart';
import '../core/l10n/l10n.dart';

const _bg = Color(0xFF0F172A);
const _line = Color(0xFF1E293B);
const _accent = Color(0xFF5EEAD4);

class SqlDock extends StatefulWidget {
  /// ความสูงกำหนดโดยกล่องที่ห่อ (หน้าหลักห่อด้วย SizedBox: ตอนย่อ 44 ตอนขยายตามที่ผู้ใช้ลากปรับ)
  const SqlDock({super.key});

  @override
  State<SqlDock> createState() => _SqlDockState();
}

class _SqlDockState extends State<SqlDock> {
  bool _copied = false;
  Timer? _copyTimer;

  @override
  void dispose() {
    _copyTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy(String sql) async {
    await Clipboard.setData(ClipboardData(text: sql));
    if (!mounted) return;
    setState(() => _copied = true);
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    final cv = context.watch<CanvasController>();
    final dialect = c.project.dialect;
    final sql = DdlGenerator.forDialect(dialect).generate(c.project);
    final lines = sql.endsWith('\n') ? sql.substring(0, sql.length - 1).split('\n') : sql.split('\n');

    return Container(
      color: _bg,
      child: Column(children: [
        _header(c, cv, dialect, sql),
        if (!cv.dockCollapsed)
          Expanded(child: cv.dockTab == DockTab.sql ? _body(lines) : _issues(c)),
      ]),
    );
  }

  Widget _tab(CanvasController cv, DockTab tab, String label, {int badge = 0}) {
    final on = cv.dockTab == tab;
    return InkWell(
      onTap: () => cv.showDock(tab),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: on ? _accent : Colors.transparent, width: 2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  color: on ? Colors.white : const Color(0xFFCBD5E1),
                  fontSize: 13,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
          if (badge > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(9)),
              child: Text('$badge',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF3B2300))),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _issues(ProjectController c) {
    final issues = c.issues;
    if (issues.isEmpty) {
      return Center(
        child: Text(tr('✓ ไม่พบปัญหา — พร้อม Export'),
            style: TextStyle(color: Color(0xFF7DD3C0), fontSize: 13)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: issues.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        if (i == 0) {
          return Text(issueSummary(issues),
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12));
        }
        final issue = issues[i - 1];
        return IssueCard(
          issue: issue,
          onTap: issue.tableId == null
              ? null
              : () => c.selectTable(issue.tableId, columnId: issue.columnId),
        );
      },
    );
  }

  Widget _header(ProjectController c, CanvasController cv, Dialect dialect, String sql) {
    final badge = c.issues.where((i) => i.severity != Severity.info).length;
    return Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
        child: Row(children: [
          // หน้าต่างแคบ: ย่อแท็บและกลุ่มปุ่ม dialect ลงแทนการล้น
          // (flex สูงเพื่อให้สองกลุ่มนี้ได้พื้นที่ก่อน Spacer — ไม่งั้น Spacer แบ่งพื้นที่ครึ่งหนึ่งทั้งที่ว่างเปล่า)
          Flexible(
            flex: 1000,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _tab(cv, DockTab.sql, 'SQL Preview'),
                _tab(cv, DockTab.issues, tr('ปัญหา'), badge: badge),
              ]),
            ),
          ),
          const Spacer(),
          Flexible(
            flex: 1000,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: _dialectSwitch(c, dialect),
            ),
          ),
          const SizedBox(width: 8),
          if (cv.dockTab == DockTab.sql)
            OutlinedButton(
              onPressed: () => _copy(sql),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE2E8F0),
                side: const BorderSide(color: Color(0xFF334155)),
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 12.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
              ),
              child: Text(_copied ? tr('คัดลอกแล้ว ✓') : tr('คัดลอก')),
            ),
          IconButton(
            tooltip: cv.dockCollapsed ? tr('ขยายแผง SQL') : tr('ย่อแผง SQL'),
            onPressed: cv.toggleDockCollapsed,
            icon: Icon(cv.dockCollapsed ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: const Color(0xFFCBD5E1)),
          ),
        ]),
      );
  }

  Widget _dialectSwitch(ProjectController c, Dialect dialect) => Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF334155)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final d in Dialect.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Tooltip(
                    message: 'Alt+${d.index + 1}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => c.setDialect(d),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: d == dialect ? _accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(d.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: d == dialect ? const Color(0xFF042F2E) : const Color(0xFFCBD5E1),
                            )),
                      ),
                    ),
                  ),
                ),
            ]),
          );

  Widget _body(List<String> lines) => SqlCodeView(lines: lines);
}
