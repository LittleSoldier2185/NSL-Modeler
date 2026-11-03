import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import 'theme.dart';

/// สิ่งที่แถบชื่อหน้าต่างแบบกำหนดเองต้องใช้จากระบบหน้าต่าง (แยกเป็น interface เพื่อให้เทสต์ใช้ตัวปลอมได้)
abstract class WindowBackend {
  Future<void> minimize();
  Future<void> toggleMaximize();
  Future<void> startDrag();

  /// ปิดหน้าต่างจริง (เรียกหลังผ่านการถามบันทึกแล้ว)
  Future<void> destroy();
  Future<bool> isMaximized();

  /// ส่งค่าใหม่ทุกครั้งที่หน้าต่างขยาย/คืนขนาด
  Stream<bool> get maximizedChanges;
}

/// สถานะแถบชื่อหน้าต่างของแอป: มี [backend] = ซ่อนแถบของระบบแล้วใช้แถบของเราเอง
///
/// ใช้เฉพาะ Windows: โค้ดฝั่ง runner (windows/runner/flutter_window.cpp) ตัดแถบชื่อของระบบออก
/// แต่คงขอบปรับขนาด/snap/เงาไว้ และรับคำสั่งจากช่อง "nsl_modeler/window"
/// ระบบอื่นยังใช้แถบชื่อของระบบตามปกติ
class WindowChrome {
  WindowChrome._();

  static WindowBackend? backend;

  /// ระยะเว้นซ้ายของแถบบน (ไว้เผื่อระบบที่มีปุ่มของระบบอยู่มุมซ้าย — ตอนนี้ไม่ใช้)
  static double leadingInset = 0;

  /// ปุ่ม minimize/maximize/close ของเราเอง
  static bool get customControls => backend != null && leadingInset == 0;

  /// ผู้ขอปิดหน้าต่าง (HomePage ตั้งให้ถามบันทึกก่อน); ไม่มี = ปิดเลย
  static Future<void> Function()? closeHandler;

  static Future<void> requestClose() async {
    final h = closeHandler;
    if (h != null) {
      await h();
    } else {
      await backend?.destroy();
    }
  }

  /// เริ่มช่องสื่อสารกับ runner ล้มเหลว (เช่นรันบนระบบอื่น/เทสต์) ก็ใช้แถบเดิมต่อ ไม่ให้แอปเปิดไม่ขึ้น
  static Future<void> initDesktop() async {
    if (!Platform.isWindows) return;
    try {
      final be = _ChannelBackend();
      await be.start();
      backend = be;
    } catch (_) {
      backend = null;
    }
  }
}

class _ChannelBackend implements WindowBackend {
  static const _channel = MethodChannel('nsl_modeler/window');
  final _max = StreamController<bool>.broadcast();

  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'closeRequested':
          // ปิดจากปุ่มของระบบ/Alt+F4/taskbar: ถามบันทึกก่อน
          unawaited(WindowChrome.requestClose());
        case 'maximized':
          _max.add(call.arguments == true);
      }
      return null;
    });
    // แจ้ง runner ว่าฝั่ง Dart พร้อมรับคำขอปิดแล้ว (ก่อนหน้านั้น runner ปิดเองเลย)
    await _channel.invokeMethod<void>('ready');
  }

  @override
  Future<void> minimize() => _channel.invokeMethod<void>('minimize');

  @override
  Future<void> toggleMaximize() => _channel.invokeMethod<void>('toggleMaximize');

  @override
  Future<void> startDrag() => _channel.invokeMethod<void>('startDrag');

  @override
  Future<void> destroy() => _channel.invokeMethod<void>('destroy');

  @override
  Future<bool> isMaximized() async => (await _channel.invokeMethod<bool>('isMaximized')) ?? false;

  @override
  Stream<bool> get maximizedChanges => _max.stream;
}

/// ลากพื้นที่ว่างของแถบบนเพื่อย้ายหน้าต่าง; ดับเบิลคลิก = ขยาย/คืนขนาด (ไม่มี backend = ไม่ทำอะไร)
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final be = WindowChrome.backend;
    if (be == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => be.startDrag(),
      onDoubleTap: be.toggleMaximize,
      child: child,
    );
  }
}

/// ปุ่ม ย่อ / ขยาย-คืนขนาด / ปิด แบบ Windows ชิดมุมขวาบน
class WindowControls extends StatefulWidget {
  const WindowControls({super.key, this.height = 52});
  final double height;

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> {
  bool _maximized = false;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    final be = WindowChrome.backend;
    if (be == null) return;
    be.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
    _sub = be.maximizedChanges.listen((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final be = WindowChrome.backend;
    if (be == null) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _CaptionButton(
        key: const ValueKey('win-min'),
        icon: Icons.remove_rounded,
        tooltip: tr('ย่อหน้าต่าง'),
        height: widget.height,
        onTap: be.minimize,
      ),
      _CaptionButton(
        key: const ValueKey('win-max'),
        icon: _maximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
        iconSize: _maximized ? 14 : 16,
        tooltip: _maximized ? tr('คืนขนาดหน้าต่าง') : tr('ขยายเต็มจอ'),
        height: widget.height,
        onTap: be.toggleMaximize,
      ),
      _CaptionButton(
        key: const ValueKey('win-close'),
        icon: Icons.close_rounded,
        tooltip: tr('ปิด'),
        height: widget.height,
        danger: true,
        onTap: WindowChrome.requestClose,
      ),
    ]);
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.height,
    required this.onTap,
    this.danger = false,
    this.iconSize = 17,
  });
  final IconData icon;
  final String tooltip;
  final double height;
  final VoidCallback onTap;
  final bool danger;
  final double iconSize;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hover ? (widget.danger ? const Color(0xFFE81123) : C.text.withValues(alpha: 0.09)) : Colors.transparent;
    final fg = _hover && widget.danger ? Colors.white : C.text;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: widget.height,
            color: bg,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}
