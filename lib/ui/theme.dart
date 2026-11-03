import 'package:flutter/material.dart';

export '../core/types/type_label.dart';

/// สีและสไตล์ตามดีไซน์ "NSL Modeler — หน้าหลัก"
class C {
  static const bg = Color(0xFFEEF1F5);
  static const canvas = Color(0xFFF6F8FB);
  static const dot = Color(0xFFC3CCD8);
  static const surface = Colors.white;
  static const border = Color(0xFFD8DEE6);
  static const borderSoft = Color(0xFFE6EAF0);
  static const inputBorder = Color(0xFFCBD3DE);
  static const text = Color(0xFF1B2430);
  static const muted = Color(0xFF5B6778);
  static const primary = Color(0xFF0F766E);
  static const primaryDark = Color(0xFF0B5A54);
  static const primaryTint = Color(0xFFE2F3F1);
  static const tableHead = Color(0xFF1F2A37);
  static const warnBg = Color(0xFFFFF4D6);
  static const warnText = Color(0xFF5C3D00);
  static const infoBg = Color(0xFFE8EEF8);
  static const infoText = Color(0xFF1E3A6B);
  static const field = Color(0xFFF3F5F8);

  static const pkBg = Color(0xFFFDEBD3);
  static const pkText = Color(0xFF8A4B08);
  static const uqBg = Color(0xFFEDE9FE);
  static const uqText = Color(0xFF5B21B6);
  static const nnBg = Color(0xFFE6EAF0);
  static const nnText = Color(0xFF334155);
}

const kThai = 'IBM Plex Sans Thai';
const kMono = 'JetBrains Mono';

const monoStyle = TextStyle(fontFamily: kMono, fontFamilyFallback: ['Consolas']);

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      fontFamily: kThai,
      fontFamilyFallback: const ['Leelawadee UI', 'Tahoma', 'Segoe UI'],
      scaffoldBackgroundColor: C.bg,
      colorScheme: ColorScheme.fromSeed(seedColor: C.primary, surface: C.surface),
      textTheme: ThemeData.light().textTheme.apply(bodyColor: C.text, displayColor: C.text),
      dividerColor: C.borderSoft,
    );

