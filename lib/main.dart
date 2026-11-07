import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'core/models/workspace.dart';
import 'core/db/saved_connections.dart';
import 'core/db/secret_codec.dart';
import 'core/storage/autosave.dart';
import 'core/storage/project_file.dart';
import 'core/l10n/l10n.dart';
import 'state/app_settings.dart';
import 'state/autosave_coordinator.dart';
import 'state/dfd_controller.dart';
import 'state/flowchart_controller.dart';
import 'state/project_controller.dart';
import 'state/workspace_controller.dart';
import 'ui/canvas/canvas_controller.dart';
import 'ui/db_connect_dialog.dart';
import 'ui/home_page.dart';
import 'ui/window_chrome.dart';
import 'ui/theme.dart';

Future<void> main(List<String> args) async {
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
    DbConnectDialog.store = SavedConnectionStore(
      File('${dir.path}${Platform.pathSeparator}connections.json'),
      WindowsDpapiCodec.forPlatform(),
    );
    recovery = await store.readRecoverable();
  } catch (_) {
    store = null;
  }
  // ดับเบิลคลิกไฟล์ .nsld / .nslm / .erd (หรือ nsl_dev.exe <ไฟล์>) = เปิดไฟล์นั้นทันที ไม่ถามกู้คืนงานค้าง
  Workspace? initial;
  String? initialPath;
  for (final a in args) {
    final lower = a.toLowerCase();
    if (!kOpenableExts.any((e) => lower.endsWith('.$e'))) continue;
    try {
      initial = await ProjectFile.load(a);
      initialPath = a;
      recovery = null;
    } catch (_) {}
    break;
  }
  // หาที่เก็บไม่ได้ = ใช้ค่าเริ่มต้น (ไทย/สว่าง) โดยไม่ถามภาษา เพราะบันทึกคำตอบไม่ได้อยู่ดี
  runApp(NslDevApp(autosave: store, recovery: recovery, settings: settings ?? AppSettings(lang: Lang.th), initialProject: initial, initialPath: initialPath));
}

class NslDevApp extends StatefulWidget {
  const NslDevApp({super.key, this.autosave, this.recovery, this.settings, this.initialProject, this.initialPath});

  /// โปรเจกต์ที่เปิดตั้งแต่เริ่ม (จากไฟล์ที่ส่งมาทางบรรทัดคำสั่ง) — null = เริ่มว่าง
  final Workspace? initialProject;
  final String? initialPath;

  /// การตั้งค่าแอป (null = ค่าเริ่มต้น ไทย/สว่าง ไม่ถามภาษา)
  final AppSettings? settings;

  /// ที่เก็บ auto-save (null = ปิด auto-save)
  final AutosaveStore? autosave;

  /// งานค้างจากครั้งก่อนที่จะถามผู้ใช้ว่าจะกู้คืนไหม
  final AutosaveInfo? recovery;

  @override
  State<NslDevApp> createState() => _NslDevAppState();
}

class _NslDevAppState extends State<NslDevApp> with WidgetsBindingObserver {
  late final AppSettings _settings = widget.settings ?? AppSettings(lang: Lang.th);
  bool _recoveryPending = true;
  late final WorkspaceController _workspace = WorkspaceController();
  late final CanvasController _canvas = CanvasController();
  late final AutosaveCoordinator? _autosave =
      widget.autosave == null ? null : AutosaveCoordinator(_workspace, widget.autosave!);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settings.addListener(_onSettings);
    final p = widget.initialProject;
    if (p != null) _workspace.loadWorkspace(p, widget.initialPath);
    _workspace.addListener(_onWorkspace);
    _onWorkspace();
  }

  void _onSettings() => setState(() {});

  /// มุมมอง (เลื่อน/ซูม) ของแคนวาส ER แยกต่อเอกสาร
  void _onWorkspace() => _canvas.showDoc(_workspace.currentEr.docId);

  /// หน้าต่างเสียโฟกัส/ถูกซ่อน/กำลังปิด -> เขียนสำเนาทันที ไม่รอ timer
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _autosave?.flush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_onSettings);
    _workspace.removeListener(_onWorkspace);
    _autosave?.dispose();
    _workspace.dispose();
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
        ChangeNotifierProvider.value(value: _workspace),
        ChangeNotifierProvider.value(value: _canvas),
        Provider<AutosaveCoordinator?>.value(value: _autosave),
      ],
      // controller ของเอกสาร ER/DFD/Flowchart ที่ใช้งานอยู่: เปลี่ยนตามแท็บ (วิดเจ็ตเดิมใช้ watch<ProjectController>() ได้ต่อ)
      child: ListenableBuilder(
        listenable: _workspace,
        builder: (context, child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectController>.value(value: _workspace.currentEr),
            ChangeNotifierProvider<DfdController>.value(value: _workspace.currentDfd),
            ChangeNotifierProvider<FlowchartController>.value(value: _workspace.currentFlowchart),
          ],
          child: child,
        ),
        child: MaterialApp(
          key: ValueKey('${_settings.lang.code}-${_settings.dark}'),
          title: 'NSL Dev',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(palette),
          home: HomePage(
            recovery: _recoveryPending ? widget.recovery : null,
            onRecoveryOffered: () => _recoveryPending = false,
          ),
        ),
      ),
    );
  }
}
