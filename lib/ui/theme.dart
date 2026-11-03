import 'package:flutter/material.dart';

export '../core/types/type_label.dart';

/// ชุดสีของหนึ่งธีม
class Palette {
  const Palette({
    required this.brightness,
    required this.bg,
    required this.canvas,
    required this.dot,
    required this.surface,
    required this.surfaceHi,
    required this.border,
    required this.borderSoft,
    required this.inputBorder,
    required this.text,
    required this.muted,
    required this.primary,
    required this.primaryDark,
    required this.primaryTint,
    required this.tableHead,
    required this.warnBg,
    required this.warnText,
    required this.infoBg,
    required this.infoText,
    required this.field,
    required this.pkBg,
    required this.pkText,
    required this.uqBg,
    required this.uqText,
    required this.nnBg,
    required this.nnText,
    required this.shadow,
  });

  final Brightness brightness;
  final Color bg, canvas, dot, surface, surfaceHi, border, borderSoft, inputBorder;
  final Color text, muted, primary, primaryDark, primaryTint, tableHead;
  final Color warnBg, warnText, infoBg, infoText, field;
  final Color pkBg, pkText, uqBg, uqText, nnBg, nnText;

  /// สีเงา (ธีมมืดต้องเข้มกว่าเพื่อให้เห็นความลึก)
  final Color shadow;
}

const kLightPalette = Palette(
  brightness: Brightness.light,
  bg: Color(0xFFEEF1F5),
  canvas: Color(0xFFF6F8FB),
  dot: Color(0xFFC3CCD8),
  surface: Colors.white,
  surfaceHi: Colors.white,
  border: Color(0xFFD8DEE6),
  borderSoft: Color(0xFFE6EAF0),
  inputBorder: Color(0xFFCBD3DE),
  text: Color(0xFF1B2430),
  muted: Color(0xFF5B6778),
  primary: Color(0xFF0F766E),
  primaryDark: Color(0xFF0B5A54),
  primaryTint: Color(0xFFE2F3F1),
  tableHead: Color(0xFF1F2A37),
  warnBg: Color(0xFFFFF4D6),
  warnText: Color(0xFF5C3D00),
  infoBg: Color(0xFFE8EEF8),
  infoText: Color(0xFF1E3A6B),
  field: Color(0xFFF3F5F8),
  pkBg: Color(0xFFFDEBD3),
  pkText: Color(0xFF8A4B08),
  uqBg: Color(0xFFEDE9FE),
  uqText: Color(0xFF5B21B6),
  nnBg: Color(0xFFE6EAF0),
  nnText: Color(0xFF334155),
  shadow: Color(0xFF0F172A),
);

const kDarkPalette = Palette(
  brightness: Brightness.dark,
  bg: Color(0xFF0E1319),
  canvas: Color(0xFF121820),
  dot: Color(0xFF2A3544),
  surface: Color(0xFF19212B),
  surfaceHi: Color(0xFF212B37),
  border: Color(0xFF2E3946),
  borderSoft: Color(0xFF242E3A),
  inputBorder: Color(0xFF3B4859),
  text: Color(0xFFE6EBF2),
  muted: Color(0xFF9AA7B8),
  primary: Color(0xFF14958B),
  primaryDark: Color(0xFF5ED0C4),
  primaryTint: Color(0xFF133533),
  tableHead: Color(0xFF2A3848),
  warnBg: Color(0xFF3A2E10),
  warnText: Color(0xFFF4D58A),
  infoBg: Color(0xFF1B2A44),
  infoText: Color(0xFF9DBBEA),
  field: Color(0xFF222C38),
  pkBg: Color(0xFF4A3213),
  pkText: Color(0xFFF5B66B),
  uqBg: Color(0xFF2E2552),
  uqText: Color(0xFFC4B0FA),
  nnBg: Color(0xFF2A3441),
  nnText: Color(0xFFB5C0CE),
  shadow: Color(0xFF000000),
);

/// สีและสไตล์ตามดีไซน์ "NSL Modeler — หน้าหลัก"
///
/// อ่านจากพาเลตต์ที่ใช้อยู่ตอนนี้ ([use]) — ตอนสลับธีมแอปจะสร้างต้นไม้วิดเจ็ตใหม่ทั้งหมด
class C {
  static Palette _p = kLightPalette;

  static Palette get palette => _p;
  static bool get isDark => _p.brightness == Brightness.dark;
  static void use(Palette p) => _p = p;

  /// รันงานด้วยพาเลตต์ที่กำหนดชั่วคราว (ใช้ตอน export ภาพ ให้ได้สีสว่างเสมอไม่ว่าธีมแอปเป็นอะไร)
  static T withPalette<T>(Palette p, T Function() body) {
    final prev = _p;
    _p = p;
    try {
      return body();
    } finally {
      _p = prev;
    }
  }

  static Color get bg => _p.bg;
  static Color get canvas => _p.canvas;
  static Color get dot => _p.dot;
  static Color get surface => _p.surface;
  static Color get surfaceHi => _p.surfaceHi;
  static Color get border => _p.border;
  static Color get borderSoft => _p.borderSoft;
  static Color get inputBorder => _p.inputBorder;
  static Color get text => _p.text;
  static Color get muted => _p.muted;
  static Color get primary => _p.primary;
  static Color get primaryDark => _p.primaryDark;
  static Color get primaryTint => _p.primaryTint;
  static Color get tableHead => _p.tableHead;
  static Color get warnBg => _p.warnBg;
  static Color get warnText => _p.warnText;
  static Color get infoBg => _p.infoBg;
  static Color get infoText => _p.infoText;
  static Color get field => _p.field;

  /// พื้นนอกกรอบกระดาน (เข้มกว่าพื้นกระดาน เพื่อให้เห็นขอบ)
  static Color get boardOutside => isDark ? const Color(0xFF0A0E13) : const Color(0xFFE2E7EE);
  static Color get boardEdge => isDark ? const Color(0xFF3F4E62) : const Color(0xFFB4BFCD);

  /// สีอันตราย (ลบ / error)
  static Color get danger => isDark ? const Color(0xFFF97066) : const Color(0xFFB42318);
  static Color get dangerBg => isDark ? const Color(0xFF3F1B1B) : const Color(0xFFFDE8E8);
  static Color get dangerText => isDark ? const Color(0xFFFCA5A5) : const Color(0xFF7A1F1F);

  /// แถวที่กำลังเป็นต้นทางของการลากเส้น FK
  static Color get fkSource => isDark ? const Color(0xFF5A4A12) : const Color(0xFFFFE9A8);
  static Color get fkChip => isDark ? const Color(0xFF16403D) : const Color(0xFFD9F0EC);

  static Color get pkBg => _p.pkBg;
  static Color get pkText => _p.pkText;
  static Color get uqBg => _p.uqBg;
  static Color get uqText => _p.uqText;
  static Color get nnBg => _p.nnBg;
  static Color get nnText => _p.nnText;

  // ---- ความลึก (elevation) ----
  static Color _sh(double a) => _p.shadow.withValues(alpha: isDark ? (a * 2.4).clamp(0, 1) : a);

  /// ยกเล็กน้อย: ปุ่ม, ช่องค้นหา
  static List<BoxShadow> get shadowSm => [
        BoxShadow(color: _sh(0.06), blurRadius: 2, offset: const Offset(0, 1)),
        BoxShadow(color: _sh(0.06), blurRadius: 6, offset: const Offset(0, 2)),
      ];

  /// ยกปานกลาง: การ์ดตาราง, แผงลอย
  static List<BoxShadow> get shadowMd => [
        BoxShadow(color: _sh(0.07), blurRadius: 3, offset: const Offset(0, 1)),
        BoxShadow(color: _sh(0.10), blurRadius: 14, offset: const Offset(0, 6)),
      ];

  /// ลอยสูง: ตารางที่เลือก/กำลังลาก, เมนู, dialog
  static List<BoxShadow> get shadowLg => [
        BoxShadow(color: _sh(0.10), blurRadius: 6, offset: const Offset(0, 2)),
        BoxShadow(color: _sh(0.16), blurRadius: 28, offset: const Offset(0, 14)),
      ];

  /// เงาเข้าด้านบนของแผงด้านข้าง/แถบบน ให้เห็นว่าแผงอยู่เหนือ canvas
  static List<BoxShadow> get shadowBar => [
        BoxShadow(color: _sh(0.08), blurRadius: 10, offset: const Offset(0, 2)),
      ];
}

/// ฟอนต์หลักของแอป (ไทย + อังกฤษ): Noto Sans Thai แพ็กมากับแอป (assets/fonts)
const kThai = 'Noto Sans Thai';

/// ฟอนต์สำรองสำหรับสัญลักษณ์ที่ Noto Sans Thai ไม่มี (เช่น ● ✓ →) — ใช้ฟอนต์ที่มากับระบบ
const kFontFallback = ['Leelawadee UI', 'Segoe UI Symbol', 'Segoe UI', 'Tahoma'];
const kMono = 'JetBrains Mono';

/// ใส่ฟอนต์ที่ผู้ใช้เลือกให้ตาราง ([family] = ชื่อฟอนต์ที่ติดตั้งในเครื่อง) — null = ไม่เปลี่ยน (ใช้ Noto Sans Thai)
/// ฟอนต์ที่ไม่มีอักษรไทยหรือไม่มีในเครื่องจะตกไปใช้ Noto Sans Thai ตามลำดับสำรอง
TextStyle tableFont(TextStyle base, String? family) =>
    family == null ? base : base.copyWith(fontFamily: family, fontFamilyFallback: [kThai, ...kFontFallback]);

const monoStyle = TextStyle(fontFamily: kMono, fontFamilyFallback: ['Consolas']);

ThemeData buildTheme([Palette p = kLightPalette]) {
  final dark = p.brightness == Brightness.dark;
  final base = dark ? ThemeData.dark() : ThemeData.light();
  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    fontFamily: kThai,
    fontFamilyFallback: kFontFallback,
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: kLightPalette.primary, brightness: p.brightness, surface: p.surface)
        .copyWith(primary: p.primary, onPrimary: Colors.white),
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
    dividerColor: p.borderSoft,
    canvasColor: p.surface,
    dialogTheme: DialogThemeData(
      backgroundColor: p.surfaceHi,
      elevation: 12,
      shadowColor: p.shadow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.borderSoft)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surfaceHi,
      elevation: 10,
      shadowColor: p.shadow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: p.borderSoft)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? p.surfaceHi : p.tableHead,
      contentTextStyle: const TextStyle(color: Colors.white, fontFamily: kThai),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: dark ? p.surfaceHi : p.tableHead, borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: kThai),
    ),
  );
}
