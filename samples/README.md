# ไฟล์ SQL ตัวอย่างสำหรับทดสอบ

ใช้กับเมนู **ไฟล์ > นำเข้าจาก .sql…** (หรือ Ctrl+I) เพื่อดูว่าโปรแกรมอ่านโครงสร้างแล้ววาดเป็นแผนภาพได้ถูกต้องไหม

| ไฟล์ | Dialect | ตาราง | จุดที่ใช้ทดสอบ |
|------|---------|-------|----------------|
| `shop_mysql.sql` | MySQL / MariaDB | 7 | FK 1:N, ตารางเชื่อม N:M (PK ผสม), self-reference, `ALTER TABLE … ADD CONSTRAINT`, INDEX, `COMMENT` |
| `blog_postgres.sql` | PostgreSQL | 5 | `SERIAL`/`BIGSERIAL`, `BOOLEAN`, FK ผ่าน `ALTER TABLE`, `CREATE UNIQUE INDEX`, `COMMENT ON` |
| `school_sqlite.sql` | SQLite | 4 | FK ในตัว `CREATE TABLE`, `AUTOINCREMENT`, PK ผสม 3 คอลัมน์ |

`shop_mysql.sql` และ `school_sqlite.sql` มีคำสั่ง `SET NAMES` / `PRAGMA` ตั้งใจใส่ไว้ เพื่อดูแผง "สิ่งที่ควรตรวจ" ที่แจ้งว่าข้ามคำสั่งที่ไม่ใช่โครงสร้างตาราง ส่วน `blog_postgres.sql` นำเข้าได้โดยไม่มีคำเตือน

ทดสอบต่อได้ด้วยการนำเข้าแล้วสลับ dialect เป็นตัวอื่น จากนั้น Export `.sql` เพื่อดูว่าแปลงชนิดข้อมูลถูกต้อง
หรือใช้ **เปรียบเทียบกับไฟล์เก่า (Migration)** หลังแก้แผนภาพ

`test/sample_sql_test.dart` นำเข้าไฟล์เหล่านี้ทุกครั้งที่รันเทสต์ เพื่อกันไม่ให้ตัวอย่างหรือ importer พังโดยไม่รู้ตัว
