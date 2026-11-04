import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// เข้ารหัส/ถอดรหัสความลับ (รหัสผ่านฐานข้อมูล) ก่อนเก็บลงไฟล์
/// คืน null เมื่อทำไม่ได้ — ผู้เรียกต้องถือว่า "ไม่จำรหัสผ่าน" ไม่ใช่เก็บเป็นข้อความเปล่า
abstract class SecretCodec {
  /// true = เข้ารหัสได้บนเครื่องนี้ (ใช้ตัดสินว่าจะเสนอ "จำรหัสผ่าน" หรือไม่)
  bool get available;

  /// ข้อความเข้ารหัส (base64) หรือ null ถ้าเข้ารหัสไม่ได้
  String? encrypt(String plain);

  /// ข้อความเดิม หรือ null ถ้าถอดไม่ได้ (เช่นไฟล์มาจากผู้ใช้/เครื่องอื่น หรือข้อมูลเสีย)
  String? decrypt(String encrypted);
}

/// ไม่เข้ารหัสอะไรเลย = ไม่เก็บความลับ (แพลตฟอร์มที่ไม่มีที่เก็บความลับของระบบ)
class NoSecretCodec implements SecretCodec {
  const NoSecretCodec();
  @override
  bool get available => false;
  @override
  String? encrypt(String plain) => null;
  @override
  String? decrypt(String encrypted) => null;
}

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _ProtectC = Int32 Function(Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, Uint32, Pointer<_DataBlob>);
typedef _ProtectD = int Function(Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, int, Pointer<_DataBlob>);
typedef _UnprotectC = Int32 Function(Pointer<_DataBlob>, Pointer<Pointer<Utf16>>, Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, Uint32, Pointer<_DataBlob>);
typedef _UnprotectD = int Function(Pointer<_DataBlob>, Pointer<Pointer<Utf16>>, Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, int, Pointer<_DataBlob>);
typedef _LocalFreeC = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFreeD = Pointer<Void> Function(Pointer<Void>);

/// Windows DPAPI (`CryptProtectData`) : ผูกกับบัญชีผู้ใช้ Windows ที่เข้ารหัส — ไฟล์ที่ก๊อปไปเครื่อง/บัญชีอื่นถอดไม่ได้
/// ไม่มีรหัสลับอยู่ในโค้ดหรือในไฟล์
class WindowsDpapiCodec implements SecretCodec {
  WindowsDpapiCodec._(this._protect, this._unprotect, this._free);

  final _ProtectD _protect;
  final _UnprotectD _unprotect;
  final _LocalFreeD _free;

  /// สร้างตัวเข้ารหัสของเครื่องนี้ : Windows = DPAPI , อื่น ๆ หรือโหลดไลบรารีไม่ได้ = [NoSecretCodec]
  static SecretCodec forPlatform() {
    if (!Platform.isWindows) return const NoSecretCodec();
    try {
      final crypt = DynamicLibrary.open('crypt32.dll');
      final kernel = DynamicLibrary.open('kernel32.dll');
      return WindowsDpapiCodec._(
        crypt.lookupFunction<_ProtectC, _ProtectD>('CryptProtectData'),
        crypt.lookupFunction<_UnprotectC, _UnprotectD>('CryptUnprotectData'),
        kernel.lookupFunction<_LocalFreeC, _LocalFreeD>('LocalFree'),
      );
    } catch (_) {
      return const NoSecretCodec();
    }
  }

  @override
  bool get available => true;

  /// ข้อความที่เข้ารหัสแล้วขึ้นต้นด้วย 'dpapi:' กันสับสนกับข้อความอื่น
  static const _prefix = 'dpapi:';

  /// entropy คงที่ของแอป (ไม่ใช่ความลับ) ให้โปรแกรมอื่นของผู้ใช้เดียวกันถอดโดยไม่ตั้งใจไม่ได้ง่าย ๆ
  static final Uint8List _entropy = Uint8List.fromList(utf8.encode('NSL-Modeler/db-connection/v1'));

  Pointer<_DataBlob> _blob(Uint8List data, Arena arena) {
    final p = arena<_DataBlob>();
    final buf = arena<Uint8>(data.isEmpty ? 1 : data.length);
    buf.asTypedList(data.length).setAll(0, data);
    p.ref
      ..cbData = data.length
      ..pbData = buf;
    return p;
  }

  @override
  String? encrypt(String plain) {
    try {
      return using((arena) {
        final input = _blob(Uint8List.fromList(utf8.encode(plain)), arena);
        final entropy = _blob(_entropy, arena);
        final out = arena<_DataBlob>();
        final ok = _protect(input, nullptr, entropy, nullptr, nullptr, 1 /* CRYPTPROTECT_UI_FORBIDDEN */, out);
        if (ok == 0) return null;
        final bytes = Uint8List.fromList(out.ref.pbData.asTypedList(out.ref.cbData));
        _free(out.ref.pbData.cast());
        return '$_prefix${base64Encode(bytes)}';
      });
    } catch (_) {
      return null;
    }
  }

  @override
  String? decrypt(String encrypted) {
    if (!encrypted.startsWith(_prefix)) return null;
    try {
      final data = base64Decode(encrypted.substring(_prefix.length));
      return using((arena) {
        final input = _blob(data, arena);
        final entropy = _blob(_entropy, arena);
        final out = arena<_DataBlob>();
        final ok = _unprotect(input, nullptr, entropy, nullptr, nullptr, 1, out);
        if (ok == 0) return null;
        final bytes = Uint8List.fromList(out.ref.pbData.asTypedList(out.ref.cbData));
        _free(out.ref.pbData.cast());
        return utf8.decode(bytes);
      });
    } catch (_) {
      return null;
    }
  }
}
