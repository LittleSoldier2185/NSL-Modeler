<p align="center">
  <img src="assets/icon/app_icon.png" alt="NSL Dev" width="128">
</p>

<h1 align="center">NSL Dev</h1>

<p align="center">
  เครื่องมือออกแบบฐานข้อมูลและแผนภาพแบบลากวาง สำหรับ Windows<br>
  <em>A drag-and-drop tool for designing databases and diagrams (Windows desktop)</em>
</p>

<p align="center">
  <strong>รุ่นปัจจุบัน: Altair 0.5.0</strong> · <a href="CHANGELOG.md">บันทึกการเปลี่ยนแปลง</a>
</p>

---

ออกแบบตาราง ความสัมพันธ์ และแผนภาพ DFD โดยลากวางบนแคนวาส แล้วสร้าง SQL สำหรับ **MySQL / MariaDB, PostgreSQL, SQLite และ SQL Server**
ทำงานบนเครื่องของคุณทั้งหมด ไม่ต้องมีบัญชีหรืออินเทอร์เน็ต

## ความสามารถ

### แผนภาพ ER
- ลากวางตาราง คอลัมน์ ความสัมพันธ์ FK (เส้นหักมุมฉากแบบ crow's foot) จัดวางอัตโนมัติ
- กลุ่มตาราง (กรอบเส้นประ) โน้ตบนแคนวาส สีและฟอนต์ต่อตาราง สีเส้น FK
- เครื่องหมายทิศทางข้อมูลกลางเส้น FK และเส้นประวิ่งตามทิศทาง (ปิดได้ในเมนูมุมมอง)
- ตรวจปัญหาของ schema ก่อน Export (เช่น ไม่มี PK, ชนิดข้อมูล FK ไม่ตรงกัน)
- ข้อมูลตั้งต้น (Seed data) สร้าง `INSERT` แบบปลอดภัยรันซ้ำได้

### แผนภาพ DFD (Data Flow Diagram)
- ผู้ใช้ภายนอก (External entity), กระบวนการ (Process), ที่เก็บข้อมูล (Data store) และเส้นข้อมูลพร้อมป้ายชื่อ ทิศทางเดียวหรือสองทาง
- ตรวจกฎของ DFD ให้อัตโนมัติ (เส้นต้องผ่านกระบวนการ, กระบวนการต้องมีข้อมูลเข้า/ออก, เลขลำดับไม่ซ้ำ ฯลฯ)
- ปรับขนาดวัตถุด้วยการลากจุดจับ, จัดวางอัตโนมัติตามทิศทางข้อมูล, กรอบขอบเขตระบบ (ลากย้ายพร้อมวัตถุข้างใน), คัดลอก-วางข้ามแท็บ/ข้ามโปรเจกต์
- แตกรายละเอียดกระบวนการเป็นแผนภาพย่อย (Level 0 → Level 1) พร้อมตรวจความสมดุลของข้อมูลเข้า/ออก (balancing)
- ผูกที่เก็บข้อมูล (Data store) กับตารางใน ER และเตือนเมื่อตารางนั้นหายไป
- แท็บแผนภาพแบบแท็บเบราว์เซอร์ สร้างหลายแผนภาพในโปรเจกต์เดียว Undo/Redo แยกต่อแท็บ

### SQL และฐานข้อมูล
- สร้าง SQL ทั้ง 4 dialect และสลับ dialect ได้ทันที
- นำเข้าจากไฟล์ `.sql` (ดูตัวอย่างใน [`samples/`](samples/README.md))
- **Migration:** เปรียบเทียบกับไฟล์เก่าหรือกับฐานข้อมูลจริง แล้วสร้างสคริปต์แก้โครงสร้าง ห่อด้วย transaction และถามยืนยันก่อนทำสิ่งที่ลบข้อมูล
- **เชื่อมต่อ MySQL / MariaDB หรือเปิดไฟล์ SQLite แบบอ่านอย่างเดียว** (เมนู ไฟล์ → เชื่อมต่อฐานข้อมูล…, `Ctrl+Shift+O`): นำโครงสร้างเข้ามาเป็นแผนภาพหรือเปรียบเทียบเพื่อสร้าง migration (ตารางที่เปลี่ยนชื่อจับคู่ด้วยมือได้ ข้อมูลจะไม่หาย) · บันทึกการเชื่อมต่อไว้ใช้ซ้ำได้
- **รัน migration กับไฟล์ SQLite โดยตรง:** ยืนยันรายการที่ข้อมูลอาจหาย → สำรองไฟล์เดิมเป็น `.bak-วันเวลา` → รันในทรานแซกชัน (ผิดพลาดยกเลิกทั้งหมด) → อ่านกลับมาตรวจว่าตรงกับแผนภาพ
- **แก้โครงสร้างตารางด้วยฟอร์มแบบ phpMyAdmin** (`Ctrl+Shift+M`): ชื่อ ชนิด ความยาว ค่าเริ่มต้น Null Index A_I ของทุกคอลัมน์ในหน้าเดียว

### การใช้งาน
- **ช่องค้นหากลางแถบชื่อหน้าต่าง** (`Ctrl+K`): ค้นข้ามแท็บได้ทั้งคำสั่ง ตาราง คอลัมน์ วัตถุ DFD โน้ต กลุ่ม และปัญหา ตัวนำหน้า `@` ตาราง · `#` คอลัมน์ · `:` DFD · `!` ปัญหา · `>` คำสั่ง · `~` โน้ต
- **แถบสถานะล่าง:** รุ่นของโปรแกรม จำนวนตาราง ปัญหาที่ตรวจพบ ซูม สถานะบันทึก และปุ่ม **มีอะไรใหม่**
- Export ภาพ PNG/SVG (ธีมสว่าง/มืด, ทั้งกระดาน/เฉพาะส่วนที่มีตาราง/เฉพาะที่เลือก), Data dictionary (Markdown), Mermaid, DBML
- ธีมสว่าง/มืด, ภาษาไทย/อังกฤษ, ฟอนต์ Noto Sans Thai ฝังในโปรแกรม
- Auto-save และกู้คืนงานที่ค้างอยู่ ไฟล์โปรเจกต์ `.nsld` (JSON) — ไฟล์ `.nslm` และ `.erd` รุ่นเก่ายังเปิดได้ และเมื่อบันทึกจะได้ไฟล์ `.nslm` ใหม่ (ไฟล์เดิมไม่ถูกแก้) ; เปิดไฟล์ด้วย `nsl_dev.exe <ไฟล์>` ได้ ; ผูกสกุล `.nslm` กับแอปใน Windows (ดับเบิลคลิกเปิดได้) ด้วย `powershell -ExecutionPolicy Bypass -File tool\register_file_association.ps1` (เฉพาะผู้ใช้ปัจจุบัน ไม่ต้องใช้สิทธิ์ผู้ดูแล ; `-ExePath` ระบุตำแหน่งแอป, `-IncludeLegacyErd` ผูก `.erd` ด้วย, `-Unregister` ถอนออก)
- กด `F1` เพื่อดูคีย์ลัดทั้งหมด (Redo = `Ctrl+Shift+Z`, `Ctrl+Y` หรือ `Alt+Z`)

## ติดตั้ง (ผู้ใช้ทั่วไป)

1. ดาวน์โหลดไฟล์ `NSL_Dev_<รุ่น>_windows_x64.zip` จากหน้า **[Releases](../../releases)**
2. แตกไฟล์ทั้งโฟลเดอร์ แล้วเปิด `nsl_dev.exe` (เก็บ `flutter_windows.dll` และโฟลเดอร์ `data` ไว้ข้างกัน)

**ข้อกำหนด:** Windows 10/11 (64 บิต) และ [Microsoft Visual C++ Redistributable (x64)](https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist)
โปรแกรมยังไม่ได้เซ็นดิจิทัล Windows SmartScreen อาจเตือน ให้เลือก "ข้อมูลเพิ่มเติม" → "เรียกใช้อยู่ดี"

## Build จากซอร์ส

ต้องมี [Flutter](https://docs.flutter.dev/get-started/install/windows/desktop) (Dart SDK ^3.13) และ Visual Studio พร้อมชุด "Desktop development with C++"
และเปิด **Developer Mode** ของ Windows (ปลั๊กอินใช้ symlink)

```bash
flutter pub get
flutter run -d windows            # รันแอป
flutter build windows --release   # ผลลัพธ์: build/windows/x64/runner/Release/
flutter test                      # เทสต์ทั้งหมด
flutter analyze
```

เปลี่ยนไอคอน Windows จาก `assets/icon/app_icon.png`: `flutter test tool/gen_app_icon_test.dart`

## โครงสร้างโปรเจกต์

```
lib/
  core/        ตรรกะล้วน ๆ ไม่ผูกกับหน้าจอ: models, ddl (สร้าง SQL), diff (migration), parser (นำเข้า .sql),
               layout (วางตาราง/เส้น), export, validate, db (เชื่อมต่อ MySQL), l10n (ไทย/อังกฤษ)
  state/       ProjectController, DfdController, AppSettings (ChangeNotifier)
  ui/          หน้าจอทั้งหมด: canvas, dfd, panels, dialogs, ฯลฯ
windows/runner/  โค้ดฝั่ง Windows (แถบชื่อหน้าต่างแบบกำหนดเอง)
samples/       ไฟล์ SQL ตัวอย่างสำหรับทดสอบ
test/          เทสต์ (unit + widget)
```

## เลขรุ่นและชื่อรุ่น

เลขรุ่นเป็น [SemVer](https://semver.org/) (`0.5.0`) ตามด้วยชื่อรุ่นเป็นดาว เรียงตามตัวอักษรทีละรุ่นที่เลขรองเพิ่ม:
0.5 **Altair** → 0.6 Betelgeuse → 0.7 Capella → 0.8 Deneb → 0.9 Elnath → 1.0 Fomalhaut
ขั้นตอนขึ้นรุ่นใหม่และสถานะงานปัจจุบันดูที่ [`progress.md`](progress.md)

## ความปลอดภัยของข้อมูล

- การเชื่อมต่อฐานข้อมูลเป็น **อ่านอย่างเดียว**: ปฏิเสธทุกคำสั่งที่ไม่ใช่ `SELECT / SHOW / DESCRIBE / EXPLAIN` และตั้ง session เป็น `READ ONLY` ที่ฝั่งเซิร์ฟเวอร์ด้วย
- **รหัสผ่านไม่ถูกบันทึก เว้นแต่คุณติ๊ก "จำรหัสผ่าน" เอง** — ค่าเริ่มต้นอยู่ในหน่วยความจำระหว่างเชื่อมต่อเท่านั้น ถ้าเลือกจำ จะเก็บเฉพาะข้อความที่เข้ารหัสด้วย Windows DPAPI (ผูกกับบัญชี Windows ของคุณ ไฟล์ที่ก๊อปไปเครื่อง/บัญชีอื่นถอดไม่ได้) ไม่มีรหัสผ่านเป็นข้อความเปล่าในไฟล์ใด ๆ
- ไฟล์ SQLite เปิดด้วยโหมดอ่านอย่างเดียว ; การรัน migration กับไฟล์ SQLite เป็นปุ่มแยกที่ต้องยืนยันและสำรองไฟล์ก่อนเสมอ
- สคริปต์ migration ห่อด้วย transaction และมีคำเตือนก่อนคำสั่งที่ลบข้อมูล

## ลิขสิทธิ์และฟอนต์

ฟอนต์ **Noto Sans Thai** ที่ฝังในโปรแกรมใช้ภายใต้ [SIL Open Font License 1.1](assets/fonts/OFL.txt)

---

## English summary

**NSL Dev** is a Windows desktop app for designing databases by drag and drop. It generates SQL for MySQL/MariaDB, PostgreSQL, SQLite and SQL Server, and also draws DFD (Data Flow Diagram) diagrams in browser-style tabs.

- **ER diagrams:** tables, columns, FK relationships (orthogonal crow's-foot lines), groups, notes, auto-layout, schema validation, seed data
- **DFD diagrams:** external entities, processes, data stores and labeled data flows with automatic rule checking
- **SQL:** import `.sql`, migration scripts (transaction-wrapped, with confirmation before destructive steps), read-only MySQL/MariaDB connection
- **Search:** a box in the title bar (`Ctrl+K`) that finds commands, tables, columns, DFD objects, notes, groups and issues across tabs (prefixes `@ # : ! > ~`)
- Export PNG/SVG (light/dark), Markdown data dictionary, Mermaid, DBML; Thai/English UI; light/dark theme

**Install:** download the zip from [Releases](../../releases), extract the whole folder and run `nsl_dev.exe` (needs the Microsoft Visual C++ Redistributable x64).
**Build:** `flutter pub get` → `flutter run -d windows` (Windows Developer Mode required). Tests: `flutter test`.
The Noto Sans Thai font is used under the SIL Open Font License 1.1.
