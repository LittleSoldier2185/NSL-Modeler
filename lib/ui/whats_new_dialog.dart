import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_info.dart';
import '../core/changelog.dart';
import '../core/l10n/l10n.dart';
import '../state/app_settings.dart';
import 'theme.dart';

/// เปิดหน้าต่าง "มีอะไรใหม่" (patch note ทุกรุ่น) และบันทึกว่าผู้ใช้เห็นรุ่นปัจจุบันแล้ว (จุดบนปุ่มหาย)
Future<void> showWhatsNew(BuildContext context) {
  context.read<AppSettings>().markNotesSeen(kAppVersion);
  return showDialog<void>(context: context, builder: (_) => const WhatsNewDialog());
}

Future<void> showAbout(BuildContext context) => showDialog<void>(context: context, builder: (_) => const AboutAppDialog());

/// patch note: เรียงรุ่นใหม่สุดก่อน แต่ละรุ่นแยกหมวด เพิ่มใหม่ / ปรับปรุง / แก้ไข
class WhatsNewDialog extends StatelessWidget {
  const WhatsNewDialog({super.key});

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.auto_awesome_rounded, size: 20, color: C.primary),
                const SizedBox(width: 10),
                Text(tr('มีอะไรใหม่'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 4),
              Text(tr('รุ่นปัจจุบัน: {0}', [appVersionLabel]), style: TextStyle(fontSize: 12.5, color: C.muted)),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  key: const ValueKey('whats-new-scroll'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final r in kReleaseNotes) _Release(note: r),
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
      );
}

class _Release extends StatelessWidget {
  const _Release({required this.note});
  final ReleaseNote note;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: C.primaryTint, borderRadius: BorderRadius.circular(6)),
              child: Text('${note.codename} ${note.version}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: C.primaryDark)),
            ),
            const SizedBox(width: 10),
            Text(note.date, style: TextStyle(fontSize: 12.5, color: C.muted)),
          ]),
          for (final k in NoteKind.values)
            if (note.of(k).isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Text(noteKindTitle(k), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.muted)),
              ),
              for (final line in note.of(k))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Icon(Icons.circle, size: 5, color: C.muted),
                    ),
                    Expanded(child: Text(tr(line), style: const TextStyle(fontSize: 13.5, height: 1.4))),
                  ]),
                ),
            ],
        ]),
      );
}

/// เกี่ยวกับโปรแกรม: โลโก้ ชื่อ รุ่น และสิทธิ์การใช้ฟอนต์
class AboutAppDialog extends StatelessWidget {
  const AboutAppDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/icon/app_icon.png', width: 96, height: 96, filterQuality: FilterQuality.medium),
            const SizedBox(height: 8),
            const Text(kAppName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(appVersionLabel, key: const ValueKey('about-version'), style: TextStyle(fontSize: 14, color: C.primaryDark, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(
              tr('เครื่องมือออกแบบฐานข้อมูลและแผนภาพแบบลากวาง'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: C.muted),
            ),
            const SizedBox(height: 10),
            Text(
              tr('ฟอนต์ Noto Sans Thai ใช้ภายใต้ SIL Open Font License'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: C.muted),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              showWhatsNew(context);
            },
            child: Text(tr('มีอะไรใหม่')),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('ปิด'))),
        ],
      );
}
