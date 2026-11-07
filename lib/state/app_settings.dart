import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/l10n/l10n.dart';

/// ขนาดแผงที่ผู้ใช้ลากปรับได้ (แผงซ้าย/ขวา กว้างกี่ px, แผง SQL ด้านล่างสูงกี่ px)
/// แจ้งเตือนเฉพาะ widget ที่ฟังอยู่ (ไม่ทำให้ทั้งแอปสร้างใหม่ระหว่างลาก)
class PanelLayout extends ChangeNotifier {
  PanelLayout({double? left, double? right, double? dock})
      : _left = _clamp(left, kLeftMin, kLeftMax, kLeftDefault),
        _right = _clamp(right, kRightMin, kRightMax, kRightDefault),
        _dock = _clamp(dock, kDockMin, kDockMax, kDockDefault);

  static const double kLeftMin = 180, kLeftMax = 480, kLeftDefault = 248;
  static const double kRightMin = 260, kRightMax = 560, kRightDefault = 320;
  static const double kDockMin = 120, kDockMax = 640, kDockDefault = 248;

  /// พื้นที่ canvas ขั้นต่ำที่ต้องเหลือเสมอ (กว้าง/สูง)
  static const double kCanvasMinWidth = 320, kCanvasMinHeight = 160;

  double _left, _right, _dock;

  static double _clamp(double? v, double min, double max, double fallback) =>
      v == null || v.isNaN ? fallback : v.clamp(min, max).toDouble();

  double get left => _left;
  double get right => _right;
  double get dock => _dock;

  void setLeft(double v) => _set(() => _left = _clamp(v, kLeftMin, kLeftMax, kLeftDefault));
  void setRight(double v) => _set(() => _right = _clamp(v, kRightMin, kRightMax, kRightDefault));
  void setDock(double v) => _set(() => _dock = _clamp(v, kDockMin, kDockMax, kDockDefault));
  void resetLeft() => setLeft(kLeftDefault);
  void resetRight() => setRight(kRightDefault);
  void resetDock() => setDock(kDockDefault);

  void _set(void Function() change) {
    final before = (_left, _right, _dock);
    change();
    if (before != (_left, _right, _dock)) notifyListeners();
  }

  /// ความกว้างแผงซ้าย/ขวาที่ใช้จริงในหน้าต่างกว้าง [total] — ถ้าหน้าต่างแคบจะบีบทั้งสองแผงตามสัดส่วน
  /// เพื่อให้ canvas เหลือพื้นที่ใช้งาน (ไม่เปลี่ยนค่าที่จำไว้)
  (double, double) effectiveWidths(double total) {
    final room = total - kCanvasMinWidth;
    if (_left + _right <= room || room < kLeftMin + kRightMin) {
      return (_left, _right);
    }
    final f = room / (_left + _right);
    var l = (_left * f).clamp(kLeftMin, kLeftMax).toDouble();
    final r = (_right * f).clamp(kRightMin, kRightMax).toDouble();
    // ปัดขั้นต่ำของแผงหนึ่งอาจทำให้ผลรวมเกินที่ว่าง: ลดแผงซ้ายชดเชย (room >= kLeftMin + kRightMin เสมอในกรณีนี้)
    if (l + r > room) l = (room - r).clamp(kLeftMin, kLeftMax).toDouble();
    return (l, r);
  }

  /// ความสูงแผง SQL ที่ใช้จริงในพื้นที่สูง [total]
  double effectiveDock(double total) {
    final room = total - kCanvasMinHeight;
    return room < kDockMin ? kDockMin : (_dock > room ? room : _dock);
  }

  Map<String, double> toJson() => {'left': _left, 'right': _right, 'dock': _dock};

  static PanelLayout fromJson(Object? j) {
    if (j is! Map) return PanelLayout();
    double? n(Object? v) => v is num ? v.toDouble() : null;
    return PanelLayout(left: n(j['left']), right: n(j['right']), dock: n(j['dock']));
  }
}

/// ความเร็วของเส้นประที่วิ่งบนเส้น FK (เวลาต่อหนึ่งรอบ)
enum FlowSpeed {
  slow(Duration(milliseconds: 1600)),
  normal(Duration(milliseconds: 900)),
  fast(Duration(milliseconds: 450));

  const FlowSpeed(this.cycle);
  final Duration cycle;

  static FlowSpeed fromName(Object? n) => values.where((v) => v.name == n).firstOrNull ?? normal;
}

/// การตั้งค่าของแอป (ภาษา, ธีม, ขนาดแผง) เก็บเป็น settings.json ในโฟลเดอร์ข้อมูลแอป
class AppSettings extends ChangeNotifier {
  AppSettings({
    Lang? lang,
    bool dark = false,
    bool snapToGrid = true,
    bool showFlow = true,
    bool flowAnimation = false,
    bool flowAlways = false,
    bool showExplorer = false,
    FlowSpeed flowSpeed = FlowSpeed.normal,
    String? lastSeenVersion,
    PanelLayout? layout,
    this.file,
  })  : layout = layout ?? PanelLayout(),
        _lastSeen = lastSeenVersion,
        // ignore: prefer_initializing_formals
        _showFlow = showFlow,
        // ignore: prefer_initializing_formals
        _flowAnim = flowAnimation,
        // ignore: prefer_initializing_formals
        _flowAlways = flowAlways,
        // ignore: prefer_initializing_formals
        _showExplorer = showExplorer,
        // ignore: prefer_initializing_formals
        _flowSpeed = flowSpeed,
        _lang = lang ?? Lang.th,
        _langChosen = lang != null,
        // ignore: prefer_initializing_formals
        _snap = snapToGrid,
        // ignore: prefer_initializing_formals
        _dark = dark {
    currentLang = _lang;
  }

  final File? file;

  /// ขนาดแผงที่ลากปรับได้ — เปลี่ยนค่าแล้วเรียก [commitLayout] ตอนลากเสร็จเพื่อบันทึกลงไฟล์
  final PanelLayout layout;
  Lang _lang;
  bool _langChosen;
  bool _dark;
  bool _snap;
  bool _showFlow;
  bool _flowAnim;
  bool _flowAlways;
  bool _showExplorer;
  FlowSpeed _flowSpeed;
  String? _lastSeen;

  Lang get lang => _lang;
  bool get dark => _dark;

  /// ลาก/วางตารางแล้วปัดเข้าช่องตาราง (กด Alt ค้างตอนลากเพื่อข้ามชั่วคราว)
  bool get snapToGrid => _snap;

  /// แสดงเครื่องหมายทิศทางข้อมูลกลางเส้น FK (วงกลมลูกศรชี้จากตารางแม่ PK ไปหาตารางลูก FK)
  bool get showFlow => _showFlow;

  /// ให้เส้นของตารางที่เลือกมีเส้นประวิ่งตามทิศทางข้อมูล (เปิดเป็นค่าเริ่มต้นในแอปจริง; ตอนสร้างแบบไม่ผ่านไฟล์ = ปิด
  /// เพราะอนิเมชันที่วิ่งไม่หยุดทำให้เทสต์ที่รอ pumpAndSettle ไม่จบ)
  bool get flowAnimation => _flowAnim;

  /// true = เส้นประวิ่งบนเส้น FK ทุกเส้นตลอดเวลา (ใช้เมื่อ [flowAnimation] เปิด) ; false = เฉพาะเส้นของตารางที่เลือก
  bool get flowAlways => _flowAlways;

  FlowSpeed get flowSpeed => _flowSpeed;

  /// แสดงแผง Project Explorer (รายการเอกสารทั้งโปรเจกต์) เหนือแผงซ้าย
  bool get showExplorer => _showExplorer;

  /// รุ่นของโปรแกรมที่ผู้ใช้เปิดดู patch note ไปแล้วล่าสุด (null = ยังไม่เคย)
  String? get lastSeenVersion => _lastSeen;

  /// มี patch note ของรุ่นปัจจุบันที่ยังไม่เคยเปิดดู (ใช้แสดงจุดบนปุ่ม "มีอะไรใหม่")
  bool hasUnseenNotes(String currentVersion) => _lastSeen != currentVersion;

  void markNotesSeen(String version) {
    if (_lastSeen == version) return;
    _lastSeen = version;
    _save();
    notifyListeners();
  }

  /// true = ผู้ใช้ยังไม่เคยเลือกภาษา (เปิดโปรแกรมครั้งแรก) -> ต้องถามก่อน
  bool get needsLanguagePrompt => !_langChosen;

  /// อ่านจากไฟล์ — ไฟล์ไม่มี/เสีย = ถือว่าเปิดครั้งแรก
  static AppSettings load(File file) {
    try {
      if (file.existsSync()) {
        final m = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        return AppSettings(
          lang: Lang.fromCode(m['lang'] as String?),
          dark: m['theme'] == 'dark',
          snapToGrid: m['snap'] != false,
          showFlow: m['flow'] != false,
          flowAnimation: m['flowAnim'] != false,
          flowAlways: m['flowAll'] != false,
          showExplorer: m['explorer'] != false,
          flowSpeed: FlowSpeed.fromName(m['flowSpeed']),
          lastSeenVersion: m['seen'] as String?,
          layout: PanelLayout.fromJson(m['layout']),
          file: file,
        );
      }
    } catch (_) {}
    return AppSettings(file: file, flowAnimation: true, flowAlways: true, showExplorer: true);
  }

  void setLang(Lang l) {
    _lang = l;
    _langChosen = true;
    currentLang = l;
    _save();
    notifyListeners();
  }

  void setDark(bool v) {
    if (_dark == v) return;
    _dark = v;
    _save();
    notifyListeners();
  }

  void toggleDark() => setDark(!_dark);

  /// บันทึกขนาดแผงลงไฟล์ (เรียกตอนลากเสร็จ ไม่เรียกทุกเฟรมระหว่างลาก)
  void commitLayout() => _save();

  void setSnapToGrid(bool v) {
    if (_snap == v) return;
    _snap = v;
    _save();
    notifyListeners();
  }

  void setShowFlow(bool v) {
    if (_showFlow == v) return;
    _showFlow = v;
    _save();
    notifyListeners();
  }

  void setFlowAnimation(bool v) {
    if (_flowAnim == v) return;
    _flowAnim = v;
    _save();
    notifyListeners();
  }

  void setFlowAlways(bool v) {
    if (_flowAlways == v) return;
    _flowAlways = v;
    _save();
    notifyListeners();
  }

  void setShowExplorer(bool v) {
    if (_showExplorer == v) return;
    _showExplorer = v;
    _save();
    notifyListeners();
  }

  void setFlowSpeed(FlowSpeed v) {
    if (_flowSpeed == v) return;
    _flowSpeed = v;
    _save();
    notifyListeners();
  }

  void _save() {
    final f = file;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode({
        if (_langChosen) 'lang': _lang.code,
        'theme': _dark ? 'dark' : 'light',
        'snap': _snap,
        'flow': _showFlow,
        'flowAnim': _flowAnim,
        'flowAll': _flowAlways,
        'explorer': _showExplorer,
        'flowSpeed': _flowSpeed.name,
        if (_lastSeen != null) 'seen': _lastSeen,
        'layout': layout.toJson(),
      }));
    } catch (_) {
      // เก็บการตั้งค่าไม่ได้ก็ใช้งานต่อได้ แค่ครั้งหน้าจะถามใหม่
    }
  }
}
