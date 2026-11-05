import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import 'theme.dart';

/// หน้าถามภาษาตอนเปิดโปรแกรมครั้งแรก — ข้อความสองภาษาเพราะยังไม่รู้ว่าผู้ใช้อ่านภาษาไหน
class LanguageDialog extends StatelessWidget {
  const LanguageDialog({super.key});

  @override
  Widget build(BuildContext context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: C.primary,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: C.shadowSm,
                  ),
                  child: const Icon(Icons.translate_rounded, size: 19, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Welcome to NSL Dev',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 14),
              Text('เลือกภาษาที่ใช้แสดงผล\nChoose your display language',
                  style: TextStyle(fontSize: 13.5, color: C.muted, height: 1.5)),
              const SizedBox(height: 4),
              Text('เปลี่ยนภายหลังได้ที่เมนู ช่วยเหลือ · You can change it later in the Help menu',
                  style: TextStyle(fontSize: 12, color: C.muted)),
              const SizedBox(height: 18),
              for (final l in Lang.values) ...[
                _Choice(lang: l, onTap: () => Navigator.pop(context, l)),
                if (l != Lang.values.last) const SizedBox(height: 10),
              ],
            ]),
          ),
        ),
      );
}

class _Choice extends StatelessWidget {
  const _Choice({required this.lang, required this.onTap});
  final Lang lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: C.field,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: C.border),
            ),
            child: Row(children: [
              Text(lang.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(Icons.arrow_forward_rounded, size: 18, color: C.muted),
            ]),
          ),
        ),
      );
}
