import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'core/storage/autosave.dart';
import 'core/l10n/l10n.dart';
import 'state/app_settings.dart';
import 'state/autosave_coordinator.dart';
import 'state/project_controller.dart';
import 'ui/canvas/canvas_controller.dart';
import 'ui/home_page.dart';
import 'ui/window_chrome.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowChrome.initDesktop(); // ซ่อนแถบชื่อของระบบ ใช้แถบบนของแอปแทน

  // auto-save: ถ้าหาที่เก็บไม่ได้ก็ทำงานต่อโดยไม่มี auto-save (ไม่ให้แอปเปิดไม่ขึ้น)
  AutosaveStore? store;
  AutosaveInfo? recovery;
  AppSettings? settings;
  try {
    final dir = await getApplicationSupportDirectory();
    settings = AppSettings.load(File('${dir.path}${Platform.pathSeparator}settings.json'));
    store = FileAutosaveStore(Directory('${dir.path}${Platform.pathSeparator}autosave'));
    recovery = await store.readRecoverable();
  } catch (_) {
    store = null;
  }
  // หาที่เก็บไม่ได้ = ใช้ค่าเริ่มต้น (ไทย/สว่าง) โดยไม่ถามภาษา เพราะบันทึกคำตอบไม่ได้อยู่ดี
  runApp(NslModelerApp(autosave: store, recovery: recovery, settings: settings ?? AppSettings(lang: Lang.th)));
}

class NslModelerApp extends StatefulWidget {
  const NslModelerApp({super.key, this.autosave, this.recovery, this.settings});

  /// การตั้งค่าแอป (null = ค่าเริ่มต้น ไทย/สว่าง ไม่ถามภาษา)
  final AppSettings? settings;

  /// ที่เก็บ auto-save (null = ปิด auto-save)
  final AutosaveStore? autosave;

  /// งานค้างจากครั้งก่อนที่จะถามผู้ใช้ว่าจะกู้คืนไหม
  final AutosaveInfo? recovery;

  @override
  State<NslModelerApp> createState() => _NslModelerAppState();
}

class _NslModelerAppState extends State<NslModelerApp> with WidgetsBindingObserver {
  late final AppSettings _settings = widget.settings ?? AppSettings(lang: Lang.th);
  bool _recoveryPending = true;
  late final ProjectController _project = ProjectController();
  late final CanvasController _canvas = CanvasController();
  late final AutosaveCoordinator? _autosave =
      widget.autosave == null ? null : AutosaveCoordinator(_project, widget.autosave!);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settings.addListener(_onSettings);
  }

  void _onSettings() => setState(() {});

  /// หน้าต่างเสียโฟกัส/ถูกซ่อน/กำลังปิด -> เขียนสำเนาทันที ไม่รอ timer
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _autosave?.flush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_onSettings);
    _autosave?.dispose();
    _project.dispose();
    _canvas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ธีม/ภาษาเปลี่ยน -> สร้างต้นไม้วิดเจ็ตใหม่ทั้งหมด (สีมาจากตัวแปรกลาง ไม่ใช่ InheritedWidget)
    final palette = _settings.dark ? kDarkPalette : kLightPalette;
    C.use(palette);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _settings),
        ChangeNotifierProvider.value(value: _project),
        ChangeNotifierProvider.value(value: _canvas),
        Provider<AutosaveCoordinator?>.value(value: _autosave),
      ],
      child: MaterialApp(
        key: ValueKey('${_settings.lang.code}-${_settings.dark}'),
        title: 'NSL Modeler',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(palette),
        home: HomePage(
          recovery: _recoveryPending ? widget.recovery : null,
          onRecoveryOffered: () => _recoveryPending = false,
        ),
      ),
    );
  }
}
