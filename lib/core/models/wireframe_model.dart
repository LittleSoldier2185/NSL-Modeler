import 'dart:math' as math;

import '../layout/box_ops.dart';
import 'color_utils.dart';
import 'workspace.dart';

/// ชนิดของชิ้นส่วนบนหน้าจอ Wireframe (ลำดับ = ลำดับในคลังชิ้นส่วน)
enum WfKind {
  container,
  heading,
  label,
  paragraph,
  button,
  input,
  textarea,
  checkbox,
  radio,
  toggle,
  select,
  slider,
  search,
  image,
  icon,
  avatar,
  table,
  list,
  card,
  tabs,
  navbar,
  sidebar,
  modal,
  divider,
  badge,
  pagination,
  breadcrumb,
  map,
  chart,
}

/// ชิ้นส่วนที่เป็น "ภาชนะ" — ชิ้นอื่นที่อยู่ข้างในทั้งใบ (และอยู่เหนือมันในลำดับการซ้อน) เป็นลูก ย้ายตามกัน
const Set<WfKind> kWfContainerKinds = {WfKind.container, WfKind.card, WfKind.modal, WfKind.sidebar, WfKind.navbar};

/// ชิ้นส่วนที่ผูกกับตาราง/คอลัมน์ใน ER ได้ (data binding อย่างง่าย)
const Set<WfKind> kWfBindableKinds = {
  WfKind.input,
  WfKind.textarea,
  WfKind.select,
  WfKind.checkbox,
  WfKind.toggle,
  WfKind.label,
  WfKind.table,
  WfKind.list,
};

/// ชิ้นส่วนที่มีสถานะ "เลือกอยู่" (checked/on)
const Set<WfKind> kWfCheckableKinds = {WfKind.checkbox, WfKind.radio, WfKind.toggle};

/// ขนาดเริ่มต้นของแต่ละชนิด
(double, double) wfDefaultSize(WfKind k) => switch (k) {
      WfKind.container => (320, 200),
      WfKind.heading => (280, 40),
      WfKind.label => (160, 24),
      WfKind.paragraph => (320, 72),
      WfKind.button => (120, 40),
      WfKind.input || WfKind.select || WfKind.search => (240, 40),
      WfKind.textarea => (280, 100),
      WfKind.checkbox || WfKind.radio => (160, 24),
      WfKind.toggle => (130, 28),
      WfKind.slider => (200, 28),
      WfKind.image => (200, 140),
      WfKind.icon => (32, 32),
      WfKind.avatar => (48, 48),
      WfKind.table => (480, 200),
      WfKind.list => (260, 180),
      WfKind.card => (260, 180),
      WfKind.tabs => (360, 40),
      WfKind.navbar => (640, 56),
      WfKind.sidebar => (220, 480),
      WfKind.modal => (420, 280),
      WfKind.divider => (300, 12),
      WfKind.badge => (72, 24),
      WfKind.pagination => (240, 36),
      WfKind.breadcrumb => (300, 24),
      WfKind.map => (320, 220),
      WfKind.chart => (320, 200),
    };

/// ขนาดตัวอักษรเริ่มต้นของแต่ละชนิด
double wfDefaultFontSize(WfKind k) => switch (k) {
      WfKind.heading => 22,
      WfKind.navbar || WfKind.modal || WfKind.card => 15,
      WfKind.badge || WfKind.breadcrumb => 12,
      _ => 14,
    };

const double kWfMinSide = 4;
const double kWfMaxSide = 8000;

/// แนวข้อความ
enum WfAlign { left, center, right }

/// รูปแบบการแสดงผลของ Wireframe ทั้งเอกสาร (มีผลกับการวาดเท่านั้น ไม่เปลี่ยนเนื้อหา)
enum WfStyle {
  /// ร่าง / low-fidelity: ขาวดำ เส้นเหมือนวาดมือ รูปภาพเป็นกากบาท
  sketch,

  /// เรียบร้อย / medium-fidelity: UI แบน สีสว่างกลาง ๆ + สีเน้น (accent)
  clean,
}

/// ขนาดหน้าจอสำเร็จรูป
enum WfDevice {
  desktop(1440, 900),
  laptop(1280, 800),
  tablet(768, 1024),
  tabletLandscape(1024, 768),
  mobile(390, 844),
  mobileSmall(360, 800),
  custom(0, 0);

  const WfDevice(this.width, this.height);
  final double width, height;
}

/// สีเน้นเริ่มต้น
const int kWfDefaultAccent = 0xFF2563EB;

/// การผูกชิ้นส่วนกับตาราง (และคอลัมน์) ในเอกสาร ER — เก็บเป็น id ล้วน
class WfDataRef {
  const WfDataRef({required this.docId, required this.tableId, this.columnId});

  final String docId;
  final String tableId;
  final String? columnId;

  Map<String, dynamic> toJson() => {'doc': docId, 'table': tableId, if (columnId != null) 'column': columnId};

  static WfDataRef? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final d = j['doc'], t = j['table'], c = j['column'];
    if (d is! String || d.isEmpty || t is! String || t.isEmpty) return null;
    return WfDataRef(docId: d, tableId: t, columnId: c is String && c.isNotEmpty ? c : null);
  }

  @override
  bool operator ==(Object other) =>
      other is WfDataRef && other.docId == docId && other.tableId == tableId && other.columnId == columnId;

  @override
  int get hashCode => Object.hash(docId, tableId, columnId);
}

/// ชิ้นส่วนหนึ่งชิ้นบนหน้าจอ (พิกัดเทียบมุมซ้ายบนของกรอบหน้าจอ)
class WfComponent implements EditableBox {
  WfComponent({
    required this.id,
    required this.kind,
    this.text = '',
    this.x = 0,
    this.y = 0,
    double? w,
    double? h,
    List<String>? columns,
    this.rows = 3,
    this.fill,
    this.stroke,
    this.textColor,
    this.fontSize,
    this.bold = false,
    this.align = WfAlign.left,
    this.disabled = false,
    this.checked = false,
    this.secondary = false,
    this.ref,
  })  : w = w ?? wfDefaultSize(kind).$1,
        h = h ?? wfDefaultSize(kind).$2,
        columns = columns ?? [];

  @override
  final String id;
  WfKind kind;

  /// ข้อความ (ปุ่ม/ป้าย/หัวข้อ/placeholder) — แท็บ/breadcrumb/dropdown/รายการ ใช้บรรทัดละรายการ
  String text;
  @override
  double x;
  @override
  double y;
  @override
  double w;
  @override
  double h;

  /// หัวคอลัมน์ของตาราง
  final List<String> columns;

  /// จำนวนแถวตัวอย่างของตาราง/รายการ
  int rows;

  /// สีพื้น/สีเส้นขอบ/สีตัวอักษร (ARGB) — null = ค่าเริ่มต้นตามรูปแบบการแสดงผล
  int? fill, stroke, textColor;

  /// ขนาดตัวอักษร — null = ค่าเริ่มต้นของชนิด
  double? fontSize;
  bool bold;
  WfAlign align;

  /// สถานะ: ใช้งานไม่ได้ (disabled) / เลือกอยู่ (checkbox, radio, switch) / ปุ่มรอง (secondary)
  bool disabled, checked, secondary;

  /// ผูกกับตาราง/คอลัมน์ใน ER (null = ไม่ผูก)
  WfDataRef? ref;

  double get right => x + w;
  double get bottom => y + h;
  double get effectiveFontSize => fontSize ?? wfDefaultFontSize(kind);

  /// รายการ (บรรทัดที่ไม่ว่าง) ของข้อความ
  List<String> get items => [for (final l in text.split('\n')) if (l.trim().isNotEmpty) l.trim()];

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'text': text,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        if (columns.isNotEmpty) 'columns': columns,
        if (rows != 3) 'rows': rows,
        if (fill != null) 'fill': fill,
        if (stroke != null) 'stroke': stroke,
        if (textColor != null) 'textColor': textColor,
        if (fontSize != null) 'fontSize': fontSize,
        if (bold) 'bold': true,
        if (align != WfAlign.left) 'align': align.name,
        if (disabled) 'disabled': true,
        if (checked) 'checked': true,
        if (secondary) 'secondary': true,
        if (ref != null) 'ref': ref!.toJson(),
      };

  /// ค่าผิดปกติ = null (ข้ามชิ้นนั้น) หรือใช้ค่าปลอดภัย
  static WfComponent? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final kind = WfKind.values.asNameMap()[j['kind']];
    if (id is! String || id.isEmpty || kind == null) return null;
    double num0(Object? v, double fb) => v is num && v.isFinite ? v.toDouble() : fb;
    final d = wfDefaultSize(kind);
    double side(Object? v, double fb) {
      final n = num0(v, fb);
      return n < kWfMinSide ? fb : math.min(n, kWfMaxSide);
    }

    final fs = j['fontSize'];
    final rows = j['rows'];
    final cols = j['columns'];
    return WfComponent(
      id: id,
      kind: kind,
      text: j['text'] is String ? j['text'] as String : '',
      x: num0(j['x'], 0).clamp(-20000, 20000).toDouble(),
      y: num0(j['y'], 0).clamp(-20000, 20000).toDouble(),
      w: side(j['w'], d.$1),
      h: side(j['h'], d.$2),
      columns: [
        if (cols is List)
          for (final c in cols.take(30)) if (c is String) c,
      ],
      rows: rows is int ? rows.clamp(0, 50) : 3,
      fill: parseArgb(j['fill']),
      stroke: parseArgb(j['stroke']),
      textColor: parseArgb(j['textColor']),
      fontSize: fs is num && fs.isFinite && fs >= 6 && fs <= 96 ? fs.toDouble() : null,
      bold: j['bold'] == true,
      align: WfAlign.values.asNameMap()[j['align']] ?? WfAlign.left,
      disabled: j['disabled'] == true,
      checked: j['checked'] == true,
      secondary: j['secondary'] == true,
      ref: WfDataRef.tryFromJson(j['ref']),
    );
  }
}

/// เนื้อหาของเอกสาร Wireframe หนึ่งชิ้น = หน้าจอหนึ่งหน้า
/// กรอบหน้าจอเริ่มที่ (0,0) ขนาด [width]×[height] ; ลำดับใน [components] = ลำดับการซ้อน (ท้ายรายการอยู่บนสุด)
class WireframeDiagram implements DocContent {
  WireframeDiagram({
    this.device = WfDevice.desktop,
    double? width,
    double? height,
    this.style = WfStyle.sketch,
    this.accent = kWfDefaultAccent,
    List<WfComponent>? components,
  })  : width = width ?? (device == WfDevice.custom ? WfDevice.desktop.width : device.width),
        height = height ?? (device == WfDevice.custom ? WfDevice.desktop.height : device.height),
        components = components ?? [];

  WfDevice device;
  double width, height;
  WfStyle style;

  /// สีเน้นของเอกสาร (ARGB ทึบ) — ใช้กับปุ่มหลัก/สวิตช์/แท็บที่เลือก ในรูปแบบ "เรียบร้อย"
  int accent;
  final List<WfComponent> components;

  static const double minFrame = 120, maxFrame = 8000;

  WfComponent? componentById(String id) {
    for (final c in components) {
      if (c.id == id) return c;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'device': device.name,
        'width': width,
        'height': height,
        'style': style.name,
        'accent': accent,
        'components': components.map((c) => c.toJson()).toList(),
      };

  @override
  Map<String, dynamic> toContentJson() => toJson();

  /// ซ่อมข้อมูลผิดปกติ: ข้ามชิ้นที่อ่านไม่ได้/id ซ้ำ ; ขนาดกรอบนอกช่วง = ขนาดของอุปกรณ์ (หรือ desktop)
  factory WireframeDiagram.fromJson(Object? j) {
    if (j is! Map) return WireframeDiagram();
    final device = WfDevice.values.asNameMap()[j['device']] ?? WfDevice.desktop;
    final fb = device == WfDevice.custom ? WfDevice.desktop : device;
    double frame(Object? v, double fallback) =>
        v is num && v.isFinite && v >= minFrame && v <= maxFrame ? v.toDouble() : fallback;
    final ids = <String>{};
    final accent = parseArgb(j['accent']);
    return WireframeDiagram(
      device: device,
      width: frame(j['width'], fb.width),
      height: frame(j['height'], fb.height),
      style: WfStyle.values.asNameMap()[j['style']] ?? WfStyle.sketch,
      accent: accent == null ? kWfDefaultAccent : (accent | 0xFF000000),
      components: [
        for (final e in (j['components'] is List ? j['components'] as List : const []))
          if (WfComponent.tryFromJson(e) case final c? when ids.add(c.id)) c,
      ],
    );
  }
}

/// พ่อของแต่ละชิ้น (id ลูก -> id พ่อ): ภาชนะที่เล็กที่สุดซึ่งอยู่ใต้ลูกในลำดับการซ้อนและครอบลูกทั้งใบ
/// (คำนวณจากตำแหน่งเสมอ จึงไม่มีลิงก์พ่อ-ลูกที่ขาด)
Map<String, String> wfParentMap(WireframeDiagram d) {
  final out = <String, String>{};
  final list = d.components;
  for (var i = 0; i < list.length; i++) {
    final c = list[i];
    WfComponent? best;
    for (var j = 0; j < i; j++) {
      final p = list[j];
      if (!kWfContainerKinds.contains(p.kind) || !boxInside(c, p)) continue;
      if (best == null || p.w * p.h <= best.w * best.h) best = p;
    }
    if (best != null) out[c.id] = best.id;
  }
  return out;
}

/// ลูกหลานทั้งหมดของชิ้น [ids] (ไม่รวมตัวเอง) ตามลำดับการซ้อน
Set<String> wfDescendants(WireframeDiagram d, Set<String> ids, [Map<String, String>? parents]) {
  final p = parents ?? wfParentMap(d);
  final out = <String>{};
  var changed = true;
  while (changed) {
    changed = false;
    for (final c in d.components) {
      final par = p[c.id];
      if (par != null && (ids.contains(par) || out.contains(par)) && !ids.contains(c.id) && out.add(c.id)) changed = true;
    }
  }
  return out;
}
