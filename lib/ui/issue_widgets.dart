import 'package:flutter/material.dart';

import '../core/validate/issue.dart';
import 'theme.dart';
import '../core/l10n/l10n.dart';

/// การ์ดแสดงปัญหา 1 รายการ สีตามระดับความรุนแรง (ตามดีไซน์: เหลือง = เตือน, ฟ้า = คำแนะนำ)
class IssueCard extends StatelessWidget {
  const IssueCard({super.key, required this.issue, this.onTap});
  final Issue issue;
  final VoidCallback? onTap;

  static (Color bg, Color fg, IconData icon) style(Severity s) => switch (s) {
        Severity.error => (C.dangerBg, C.dangerText, Icons.error_outline),
        Severity.warning => (C.warnBg, C.warnText, Icons.warning_amber_rounded),
        Severity.info => (C.infoBg, C.infoText, Icons.lightbulb_outline),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = style(issue.severity);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(issue.title,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: fg)),
                const SizedBox(height: 1),
                Text(issue.message, style: TextStyle(fontSize: 12.5, color: fg)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// สรุปจำนวนปัญหาแต่ละระดับ เช่น "2 ข้อผิดพลาด · 1 คำเตือน"
String issueSummary(List<Issue> issues) {
  int n(Severity s) => issues.where((i) => i.severity == s).length;
  final parts = [
    if (n(Severity.error) > 0) tr('{0} ข้อผิดพลาด', [n(Severity.error)]),
    if (n(Severity.warning) > 0) tr('{0} คำเตือน', [n(Severity.warning)]),
    if (n(Severity.info) > 0) tr('{0} คำแนะนำ', [n(Severity.info)]),
  ];
  return parts.isEmpty ? tr('ไม่พบปัญหา') : parts.join(' · ');
}
