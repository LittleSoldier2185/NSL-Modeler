import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../core/models/workspace.dart';
import '../state/workspace_controller.dart';
import 'canvas/context_menu.dart';
import 'document_actions.dart';
import 'theme.dart';

export 'document_actions.dart' show brokenLinkLines, docTypeIcon;

/// แท็บแผนภาพเหนือแคนวาส (แบบแท็บเอกสารของโปรแกรมกราฟิก): คลิกสลับ ลากเรียงลำดับ
/// คลิกขวา = เปลี่ยนชื่อ/ทำสำเนา/ลบ, ปุ่ม + = สร้างแผนภาพใหม่ (ER หรือ DFD) — ER อันสุดท้ายลบไม่ได้
class DiagramTabBar extends StatefulWidget {
  const DiagramTabBar({super.key});

  static const height = 36.0;

  @override
  State<DiagramTabBar> createState() => _DiagramTabBarState();
}

class _DiagramTabBarState extends State<DiagramTabBar> {
  final _scroll = ScrollController();

  /// แท็บเต็มแถบ (รายการเลื่อนได้): ปุ่ม + แยกออกมาค้างชิดขวา; ไม่เต็ม: ต่อท้ายแท็บสุดท้าย
  bool _fixedAdd = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<WorkspaceController>();
    final tabs = c.tabDocuments;
    final active = c.activeId;
    final addButton = Padding(
      padding: const EdgeInsets.only(left: 2),
      child: PopupMenuButton<DocType>(
        key: const ValueKey('tab-add'),
        tooltip: tr('สร้างแผนภาพใหม่'),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(Icons.add_rounded, size: 18, color: C.muted),
        onSelected: (k) => c.addDocument(k),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: DocType.er,
            height: 36,
            child: Text(
              tr('ER Diagram (ตารางฐานข้อมูล)'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          PopupMenuItem(
            value: DocType.dfd,
            height: 36,
            child: Text(
              tr('DFD (Data Flow Diagram)'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          PopupMenuItem(
            value: DocType.flowchart,
            height: 36,
            child: Text(
              tr('Flowchart (ผังงาน)'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
    return Container(
      height: DiagramTabBar.height,
      decoration: BoxDecoration(
        color: C.bg,
        border: Border(bottom: BorderSide(color: C.border)),
      ),
      // ปุ่ม + เป็นส่วนท้ายของรายการแท็บ: ต่อท้ายแท็บสุดท้ายเลย (แบบแท็บเบราว์เซอร์) ขยับไปทางขวาเองเมื่อมีแท็บเพิ่ม
      // แท็บเต็มแถบ = รายการเลื่อนได้ (ล้อเมาส์เลื่อนแนวนอน) ไม่ล้น
      child: Row(
        children: [
          Expanded(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (n) {
                final over = n.metrics.maxScrollExtent > 0.5;
                if (over != _fixedAdd) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _fixedAdd != over) {
                      setState(() => _fixedAdd = over);
                    }
                  });
                }
                return false;
              },
              child: Listener(
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent && _scroll.hasClients) {
                    final dy = e.scrollDelta.dy != 0
                        ? e.scrollDelta.dy
                        : e.scrollDelta.dx;
                    _scroll.jumpTo(
                      (_scroll.offset + dy).clamp(
                        0.0,
                        _scroll.position.maxScrollExtent,
                      ),
                    );
                  }
                },
                child: ReorderableListView.builder(
                  key: const ValueKey('diagram-tabs'),
                  scrollController: _scroll,
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  itemCount: tabs.length,
                  onReorderItem: (from, to) => c.reorderTab(tabs[from].id, to),
                  proxyDecorator: (child, _, _) =>
                      Material(color: Colors.transparent, child: child),
                  itemBuilder: (_, i) => ReorderableDragStartListener(
                    key: ValueKey('tab-${tabs[i].id}'),
                    index: i,
                    child: _Tab(tab: tabs[i], active: tabs[i].id == active),
                  ),
                  // ปุ่ม + ต่อท้ายแท็บสุดท้าย (ส่วนท้ายของรายการ) — แท็บเต็มแถบแล้วค้างอยู่ชิดขวาแทน (ไม่เลื่อนหาย)
                  footer: _fixedAdd ? null : addButton,
                ),
              ),
            ),
          ),
          if (_fixedAdd) addButton,
        ],
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({required this.tab, required this.active});
  final ProjectDocument tab;
  final bool active;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  Future<void> _rename(BuildContext context) => renameDocumentDialog(context, widget.tab.id);

  void _duplicate(BuildContext context) =>
      context.read<WorkspaceController>().duplicateDocument(widget.tab.id);

  Future<void> _delete(BuildContext context) => deleteDocumentDialog(context, widget.tab.id);

  @override
  Widget build(BuildContext context) {
    final c = context.read<WorkspaceController>();
    final t = widget.tab;
    final closable = c.canDeleteDocument(t.id);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => c.openDocument(t.id),
        onSecondaryTapDown: (d) {
          c.openDocument(t.id);
          showContextMenu(context, d.globalPosition, [
            MenuSpec(
              tr('เปลี่ยนชื่อ…'),
              Icons.drive_file_rename_outline,
              () => _rename(context),
            ),
            MenuSpec(
              tr('ทำสำเนาแผนภาพ'),
              Icons.copy_rounded,
              () => _duplicate(context),
            ),
            if (closable)
              MenuSpec(
                tr('ลบแผนภาพ'),
                Icons.delete_outline,
                () => _delete(context),
                danger: true,
              ),
          ]);
        },
        child: Container(
          margin: const EdgeInsets.only(right: 2),
          constraints: const BoxConstraints(minWidth: 88, maxWidth: 220),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: widget.active
                ? C.surface
                : (_hover
                      ? C.surface.withValues(alpha: 0.5)
                      : Colors.transparent),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          // เส้นเน้นด้านบนของแท็บที่เปิดอยู่ (ไม่ใช้ Border เพราะขอบสีไม่เท่ากันใช้กับมุมโค้งไม่ได้)
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 2,
                child: ColoredBox(
                  color: widget.active ? C.primary : Colors.transparent,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 6, top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      docTypeIcon(t.type),
                      size: 14,
                      color: widget.active ? C.primary : C.muted,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: widget.active
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: widget.active ? C.text : C.muted,
                        ),
                      ),
                    ),
                    if (closable) ...[
                      const SizedBox(width: 6),
                      InkResponse(
                        key: ValueKey('tab-close-${t.id}'),
                        radius: 12,
                        onTap: () => _delete(context),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: _hover || widget.active
                              ? C.muted
                              : Colors.transparent,
                        ),
                      ),
                    ] else
                      const SizedBox(width: 6),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
