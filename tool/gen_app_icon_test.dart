// สร้างไฟล์ไอคอนแอปของ Windows (windows/runner/resources/app_icon.ico) จาก assets/icon/app_icon.png
// ใช้ครั้งเดียวเมื่อเปลี่ยนไอคอน:  flutter test tool/gen_app_icon_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('สร้าง app_icon.ico หลายขนาด', () async {
    final src = File('assets/icon/app_icon.png').readAsBytesSync();
    const sizes = [16, 24, 32, 48, 64, 128, 256];
    final pngs = <Uint8List>[];
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      for (final s in sizes) {
        final codec = await ui.instantiateImageCodec(src, targetWidth: s, targetHeight: s);
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        pngs.add(data!.buffer.asUint8List());
      }
    });
    // ICO: ส่วนหัว 6 ไบต์ + รายการละ 16 ไบต์ + ข้อมูล PNG ของแต่ละขนาด
    final header = ByteData(6 + 16 * sizes.length)
      ..setUint16(2, 1, Endian.little)
      ..setUint16(4, sizes.length, Endian.little);
    var offset = 6 + 16 * sizes.length;
    for (var i = 0; i < sizes.length; i++) {
      final e = 6 + 16 * i;
      header.setUint8(e, sizes[i] == 256 ? 0 : sizes[i]);
      header.setUint8(e + 1, sizes[i] == 256 ? 0 : sizes[i]);
      header.setUint16(e + 4, 1, Endian.little); // planes
      header.setUint16(e + 6, 32, Endian.little); // bpp
      header.setUint32(e + 8, pngs[i].length, Endian.little);
      header.setUint32(e + 12, offset, Endian.little);
      offset += pngs[i].length;
    }
    final out = BytesBuilder()..add(header.buffer.asUint8List());
    for (final p in pngs) {
      out.add(p);
    }
    File('windows/runner/resources/app_icon.ico').writeAsBytesSync(out.toBytes());
    expect(File('windows/runner/resources/app_icon.ico').lengthSync(), greaterThan(1000));
  });
}
