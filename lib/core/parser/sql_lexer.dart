import '../l10n/l10n.dart';

/// ตัดคำ SQL สำหรับตัว import — รองรับ quote ของทั้ง 4 dialect:
/// `x` (MySQL), "x" (PostgreSQL/SQLite), [x] (SQL Server), 'str', N'str', คอมเมนต์ `--` และ `/* */`
enum Tk { word, ident, string, number, symbol }

class Tok {
  const Tok(this.kind, this.text, this.line, this.start, this.end);

  final Tk kind;

  /// word/symbol = ข้อความตามต้นฉบับ, ident = ชื่อที่ถอด quote แล้ว, string = เนื้อหาที่ถอด quote แล้ว
  final String text;
  final int line;
  final int start;
  final int end;

  bool isWord(String w) => kind == Tk.word && text.toUpperCase() == w;
  bool isSym(String s) => kind == Tk.symbol && text == s;

  /// ชื่อ (word หรือ ident) ที่ใช้เป็นชื่อวัตถุได้
  bool get isName => kind == Tk.word || kind == Tk.ident;

  @override
  String toString() => '$kind($text)@$line';
}

class LexResult {
  const LexResult(this.tokens, this.error, this.errorLine);
  final List<Tok> tokens;

  /// ข้อความ error ถ้าหยุดกลางคัน (สตริง/quote/คอมเมนต์ไม่ปิด) — tokens คือส่วนที่อ่านได้ก่อนหน้า
  final String? error;
  final int errorLine;
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isWordStart(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F || c == 0x40 || c == 0x23 || c > 127;
bool _isWordChar(int c) => _isWordStart(c) || _isDigit(c) || c == 0x24;

/// [backslashEscapes] = true สำหรับ MySQL (`\'` อยู่ในสตริงได้)
LexResult lexSql(String s, {bool backslashEscapes = false}) {
  final out = <Tok>[];
  var i = 0;
  var line = 1;
  final n = s.length;

  LexResult fail(String msg) => LexResult(out, msg, line);

  while (i < n) {
    final c = s.codeUnitAt(i);

    if (c == 0x0A) {
      line++;
      i++;
      continue;
    }
    if (c == 0x20 || c == 0x09 || c == 0x0D || c == 0xFEFF) {
      i++;
      continue;
    }

    // คอมเมนต์
    if (c == 0x2D && i + 1 < n && s.codeUnitAt(i + 1) == 0x2D) {
      while (i < n && s.codeUnitAt(i) != 0x0A) {
        i++;
      }
      continue;
    }
    if (c == 0x2F && i + 1 < n && s.codeUnitAt(i + 1) == 0x2A) {
      final startLine = line;
      i += 2;
      var closed = false;
      while (i < n) {
        if (s.codeUnitAt(i) == 0x0A) line++;
        if (s.codeUnitAt(i) == 0x2A && i + 1 < n && s.codeUnitAt(i + 1) == 0x2F) {
          i += 2;
          closed = true;
          break;
        }
        i++;
      }
      if (!closed) {
        line = startLine;
        return fail(tr('คอมเมนต์ /* ไม่ปิด'));
      }
      continue;
    }

    final start = i;

    // สตริง '...' (และ N'...' / E'...')
    var strStart = -1;
    if (c == 0x27) {
      strStart = i;
    } else if ((c == 0x4E || c == 0x6E || c == 0x45 || c == 0x65) &&
        i + 1 < n &&
        s.codeUnitAt(i + 1) == 0x27) {
      strStart = i + 1;
    }
    if (strStart >= 0) {
      final startLine = line;
      final buf = StringBuffer();
      i = strStart + 1;
      var closed = false;
      while (i < n) {
        final ch = s.codeUnitAt(i);
        if (ch == 0x27) {
          if (i + 1 < n && s.codeUnitAt(i + 1) == 0x27) {
            buf.write("'");
            i += 2;
            continue;
          }
          i++;
          closed = true;
          break;
        }
        if (backslashEscapes && ch == 0x5C && i + 1 < n) {
          final nx = s[i + 1];
          buf.write(switch (nx) { 'n' => '\n', 't' => '\t', 'r' => '\r', '0' => '\u0000', _ => nx });
          i += 2;
          continue;
        }
        if (ch == 0x0A) line++;
        buf.writeCharCode(ch);
        i++;
      }
      if (!closed) {
        line = startLine;
        return fail(tr('สตริงไม่ปิด'));
      }
      out.add(Tok(Tk.string, buf.toString(), startLine, start, i));
      continue;
    }

    // ชื่อที่ quote
    if (c == 0x60 || c == 0x22 || c == 0x5B) {
      final close = c == 0x5B ? 0x5D : c;
      // `[]` ของ array เช่น text[] ไม่ใช่ชื่อ
      var isIdent = true;
      if (c == 0x5B) {
        final end = s.indexOf(']', i + 1);
        isIdent = end > i + 1 && !RegExp(r'^\d+$').hasMatch(s.substring(i + 1, end)) && !s.substring(i + 1, end).contains('\n');
      }
      if (isIdent) {
        final buf = StringBuffer();
        final startLine = line;
        i++;
        var closed = false;
        while (i < n) {
          final ch = s.codeUnitAt(i);
          if (ch == close) {
            if (c != 0x5B && i + 1 < n && s.codeUnitAt(i + 1) == close) {
              buf.writeCharCode(close);
              i += 2;
              continue;
            }
            if (c == 0x5B && i + 1 < n && s.codeUnitAt(i + 1) == 0x5D) {
              buf.write(']');
              i += 2;
              continue;
            }
            i++;
            closed = true;
            break;
          }
          if (ch == 0x0A) line++;
          buf.writeCharCode(ch);
          i++;
        }
        if (!closed) {
          line = startLine;
          return fail(tr('ชื่อที่ quote ไม่ปิด'));
        }
        out.add(Tok(Tk.ident, buf.toString(), startLine, start, i));
        continue;
      }
    }

    // ตัวเลข
    if (_isDigit(c)) {
      while (i < n && _isDigit(s.codeUnitAt(i))) {
        i++;
      }
      if (i + 1 < n && s.codeUnitAt(i) == 0x2E && _isDigit(s.codeUnitAt(i + 1))) {
        i++;
        while (i < n && _isDigit(s.codeUnitAt(i))) {
          i++;
        }
      }
      out.add(Tok(Tk.number, s.substring(start, i), line, start, i));
      continue;
    }

    // คำ
    if (_isWordStart(c)) {
      while (i < n && _isWordChar(s.codeUnitAt(i))) {
        i++;
      }
      out.add(Tok(Tk.word, s.substring(start, i), line, start, i));
      continue;
    }

    // สัญลักษณ์ (:: รวมเป็นตัวเดียว)
    if (c == 0x3A && i + 1 < n && s.codeUnitAt(i + 1) == 0x3A) {
      i += 2;
      out.add(Tok(Tk.symbol, '::', line, start, i));
      continue;
    }
    i++;
    out.add(Tok(Tk.symbol, s.substring(start, i), line, start, i));
  }
  return LexResult(out, null, line);
}
