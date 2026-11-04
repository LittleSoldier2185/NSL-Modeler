import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../state/app_settings.dart';
import '../state/project_controller.dart';
import 'style_actions.dart';
import 'theme.dart';

/// ตั้งค่าเส้นความสัมพันธ์ (FK) ในที่เดียว: สีเส้น เครื่องหมายทิศทาง และเส้นประที่วิ่งตามทิศทางข้อมูล
/// การเปลี่ยนมีผลทันทีและจำไว้ในการตั้งค่าของแอป (สีเส้นเก็บในไฟล์โปรเจกต์)
Future<void> showLineSettingsDialog(BuildContext context, ProjectController c) =>
    showDialog<void>(context: context, builder: (_) => LineSettingsDialog(controller: c));

class LineSettingsDialog extends StatelessWidget {
  const LineSettingsDialog({super.key, required this.controller});
  final ProjectController controller;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    context.watch<ProjectController>();
    final lineColor = controller.project.lineColor;

    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(t, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.muted)),
        );

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('เส้นความสัมพันธ์ (FK)'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              section(tr('สี')),
              ListTile(
                key: const ValueKey('line-color'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: lineColor == null ? C.primary : Color(lineColor),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: C.border),
                  ),
                ),
                title: Text(tr('สีเส้นความสัมพันธ์ทั้งหมด')),
                subtitle: Text(lineColor == null ? tr('ค่าเริ่มต้น (ตามธีม)') : tr('กำหนดเอง')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => StyleActions.lineColor(context, controller),
              ),
              section(tr('ทิศทางข้อมูล')),
              SwitchListTile(
                key: const ValueKey('line-flow'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('แสดงทิศทางข้อมูลบนเส้น FK')),
                subtitle: Text(tr('วงกลมลูกศรกลางเส้น ชี้จากตารางแม่ (PK) ไปตารางลูก (FK)')),
                value: s.showFlow,
                onChanged: s.setShowFlow,
              ),
              section(tr('แอนิเมชัน')),
              SwitchListTile(
                key: const ValueKey('line-anim'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('เส้นประวิ่งตามทิศทางข้อมูล')),
                value: s.flowAnimation,
                onChanged: s.setFlowAnimation,
              ),
              Opacity(
                opacity: s.flowAnimation ? 1 : 0.45,
                child: IgnorePointer(
                  ignoring: !s.flowAnimation,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SwitchListTile(
                      key: const ValueKey('line-always'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('เล่นตลอดเวลา (ทุกเส้น)')),
                      subtitle: Text(s.flowAlways
                          ? tr('ทุกเส้นวิ่งตลอด แม้ไม่ได้เลือกตาราง (กินแรงเครื่องมากกว่า)')
                          : tr('วิ่งเฉพาะเส้นของตารางที่เลือก หรือเส้นที่เลือกอยู่')),
                      value: s.flowAlways,
                      onChanged: s.setFlowAlways,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(children: [
                        Text(tr('ความเร็ว'), style: TextStyle(fontSize: 13, color: C.text)),
                        const SizedBox(width: 14),
                        SegmentedButton<FlowSpeed>(
                          key: const ValueKey('line-speed'),
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: [
                            ButtonSegment(value: FlowSpeed.slow, label: Text(tr('ช้า'))),
                            ButtonSegment(value: FlowSpeed.normal, label: Text(tr('ปกติ'))),
                            ButtonSegment(value: FlowSpeed.fast, label: Text(tr('เร็ว'))),
                          ],
                          selected: {s.flowSpeed},
                          onSelectionChanged: (v) => s.setFlowSpeed(v.first),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('ปิด'))),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
