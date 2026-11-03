import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'core/storage/autosave.dart';
import 'state/autosave_coordinator.dart';
import 'state/project_controller.dart';
import 'ui/canvas/canvas_controller.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // auto-save: ถ้าหาที่เก็บไม่ได้ก็ทำงานต่อโดยไม่มี auto-save (ไม่ให้แอปเปิดไม่ขึ้น)
  AutosaveStore? store;
  AutosaveInfo? recovery;
  try {
    final dir = await getApplicationSupportDirectory();
    store = FileAutosaveStore(Directory('${dir.path}${Platform.pathSeparator}autosave'));
    recovery = await store.readRecoverable();
  } catch (_) {
    store = null;
  }
  runApp(NslModelerApp(autosave: store, recovery: recovery));
}

class NslModelerApp extends StatefulWidget {
  const NslModelerApp({super.key, this.autosave, this.recovery});

  /// ที่เก็บ auto-save (null = ปิด auto-save)
  final AutosaveStore? autosave;

  /// งานค้างจากครั้งก่อนที่จะถามผู้ใช้ว่าจะกู้คืนไหม
  final AutosaveInfo? recovery;

  @override
  State<NslModelerApp> createState() => _NslModelerAppState();
}

class _NslModelerAppState extends State<NslModelerApp> with WidgetsBindingObserver {
  late final ProjectController _project = ProjectController();
  late final CanvasController _canvas = CanvasController();
  late final AutosaveCoordinator? _autosave =
      widget.autosave == null ? null : AutosaveCoordinator(_project, widget.autosave!);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// หน้าต่างเสียโฟกัส/ถูกซ่อน/กำลังปิด -> เขียนสำเนาทันที ไม่รอ timer
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _autosave?.flush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosave?.dispose();
    _project.dispose();
    _canvas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: _project),
          ChangeNotifierProvider.value(value: _canvas),
          Provider<AutosaveCoordinator?>.value(value: _autosave),
        ],
        child: MaterialApp(
          title: 'NSL Modeler',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: HomePage(recovery: widget.recovery),
        ),
      );
}
