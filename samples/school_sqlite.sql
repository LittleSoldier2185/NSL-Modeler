-- ตัวอย่างสำหรับทดสอบ "นำเข้าจากไฟล์ .sql" (SQLite)
-- ระบบโรงเรียน: FK ในตัว CREATE TABLE, AUTOINCREMENT, ชนิดข้อมูลแบบ SQLite

PRAGMA foreign_keys = ON;

CREATE TABLE teachers (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name  TEXT NOT NULL,
    email      TEXT NOT NULL UNIQUE,
    hired_on   DATE
);

CREATE TABLE students (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    student_no  TEXT NOT NULL UNIQUE,
    full_name   TEXT NOT NULL,
    birth_date  DATE,
    gpa         REAL DEFAULT 0
);

CREATE TABLE courses (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    code        TEXT NOT NULL UNIQUE,
    title       TEXT NOT NULL,
    credits     INTEGER NOT NULL DEFAULT 3,
    teacher_id  INTEGER NOT NULL,
    FOREIGN KEY (teacher_id) REFERENCES teachers (id) ON DELETE RESTRICT
);

CREATE TABLE enrollments (
    student_id  INTEGER NOT NULL,
    course_id   INTEGER NOT NULL,
    term        TEXT    NOT NULL,
    grade       TEXT,
    PRIMARY KEY (student_id, course_id, term),
    FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
    FOREIGN KEY (course_id)  REFERENCES courses  (id) ON DELETE CASCADE
);

CREATE INDEX idx_courses_teacher ON courses (teacher_id);
CREATE INDEX idx_enrollments_course ON enrollments (course_id);
