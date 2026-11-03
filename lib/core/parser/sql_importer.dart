import '../layout/auto_layout.dart';
import '../models/column_model.dart';
import '../models/enums.dart';
import '../models/index_model.dart';
import '../models/project.dart';
import '../models/relation_model.dart';
import '../models/table_model.dart';
import 'sql_lexer.dart';

/// หมายเหตุระหว่าง import (ส่วนที่ข้าม / ไม่แน่ใจ) เพื่อให้ผู้ใช้รู้ว่าอะไรไม่ได้ถูกอ่าน
class ImportNote {
  const ImportNote(this.line, this.message, {this.warning = true});
  final int line;
  final String message;
  final bool warning;

  @override
  String toString() => 'บรรทัด $line: $message';
}

class ImportResult {
  const ImportResult(this.project, this.notes, this.detected);
  final Project project;
  final List<ImportNote> notes;
  final Dialect detected;
}

/// เดา dialect จากรูปแบบ SQL
Dialect detectDialect(String sql) {
  int count(RegExp r) => r.allMatches(sql).length;
  final score = <Dialect, int>{
    Dialect.mysql: count(RegExp('`')) +
        count(RegExp(r'\bAUTO_INCREMENT\b', caseSensitive: false)) * 3 +
        count(RegExp(r'\bENGINE\s*=', caseSensitive: false)) * 3,
    Dialect.mssql: count(RegExp(r'\[\w+\]')) +
        count(RegExp(r'\bIDENTITY\s*\(', caseSensitive: false)) * 3 +
        count(RegExp(r'^\s*GO\s*$', multiLine: true, caseSensitive: false)) * 3 +
        count(RegExp(r'\bNVARCHAR\b', caseSensitive: false)) * 2,
    Dialect.postgres: count(RegExp(r'\b(BIG|SMALL)?SERIAL\b', caseSensitive: false)) * 3 +
        count(RegExp('::')) * 2 +
        count(RegExp(r'\bBYTEA\b', caseSensitive: false)) * 2 +
        count(RegExp(r'\bCOMMENT ON\b', caseSensitive: false)) * 2,
    Dialect.sqlite: count(RegExp(r'\bAUTOINCREMENT\b', caseSensitive: false)) * 3 +
        count(RegExp(r'\bPRAGMA\b', caseSensitive: false)) * 3,
  };
  var best = Dialect.mysql;
  var bestScore = -1;
  for (final e in score.entries) {
    if (e.value > bestScore) {
      best = e.key;
      bestScore = e.value;
    }
  }
  return bestScore <= 0 ? Dialect.mysql : best;
}

/// อ่านสคริปต์ SQL (CREATE TABLE / ALTER TABLE ... ADD / CREATE INDEX / COMMENT)
/// แล้วสร้างโปรเจกต์พร้อมจัดตำแหน่งตารางให้ — คำสั่งที่ไม่รองรับจะถูกข้ามและรายงานใน [ImportResult.notes]
ImportResult importSql(String sql, {String name = 'imported', Dialect? dialect}) {
  final d = dialect ?? detectDialect(sql);
  return _Importer(sql, d, name).run();
}

class _ParseError implements Exception {
  const _ParseError(this.message);
  final String message;
}

class _Cur {
  _Cur(this.t);
  final List<Tok> t;
  int i = 0;

  bool get done => i >= t.length;
  Tok? at(int k) => i + k < t.length ? t[i + k] : null;
  Tok next() {
    if (done) throw const _ParseError('SQL จบก่อนครบประโยค');
    return t[i++];
  }

  bool isWord(String w, [int k = 0]) => at(k)?.isWord(w) ?? false;
  bool isSym(String s, [int k = 0]) => at(k)?.isSym(s) ?? false;

  bool eatWord(String w) {
    if (isWord(w)) {
      i++;
      return true;
    }
    return false;
  }

  bool eatWords(List<String> ws) {
    for (var k = 0; k < ws.length; k++) {
      if (!isWord(ws[k], k)) return false;
    }
    i += ws.length;
    return true;
  }

  bool eatSym(String s) {
    if (isSym(s)) {
      i++;
      return true;
    }
    return false;
  }
}

class _PendingFk {
  _PendingFk(this.line, this.childTable, this.childCols, this.parentTable, this.parentCols,
      this.onDelete, this.onUpdate, this.name);
  final int line;
  final String childTable;
  final List<String> childCols;
  final String parentTable;
  final List<String> parentCols;
  final RefAction onDelete;
  final RefAction onUpdate;
  final String? name;
}

class _Ref {
  _Ref(this.table, this.cols, this.onDelete, this.onUpdate);
  final String table;
  final List<String> cols;
  final RefAction onDelete;
  final RefAction onUpdate;
}

class _Importer {
  _Importer(this.src, this.dialect, this.projectName);

  final String src;
  final Dialect dialect;
  final String projectName;

  final notes = <ImportNote>[];
  final tables = <TableModel>[];
  final byName = <String, TableModel>{};
  final pending = <_PendingFk>[];
  final skipped = <String, int>{};
  var _seq = 0;

  String id(String p) => '$p${++_seq}';

  void note(int line, String msg, {bool warning = true}) => notes.add(ImportNote(line, msg, warning: warning));

  ImportResult run() {
    final lex = lexSql(src, backslashEscapes: dialect == Dialect.mysql);
    for (final st in _split(lex.tokens)) {
      try {
        _statement(st);
      } on _ParseError catch (e) {
        note(st.first.line, 'อ่านคำสั่งไม่ได้ (${e.message}) — ข้าม');
      }
    }
    if (lex.error != null) {
      note(lex.errorLine, '${lex.error} — ไฟล์ถูกอ่านถึงตรงนี้เท่านั้น');
    }
    for (final e in skipped.entries) {
      note(0, 'ข้าม ${e.value} คำสั่ง ${e.key}', warning: false);
    }
    _resolveFks();

    final project = Project(name: projectName, dialect: dialect, tables: tables);
    // ตำแหน่งตาราง
    final pos = autoLayout(project);
    for (final t in tables) {
      final p = pos[t.id];
      if (p != null) {
        t.x = p.x;
        t.y = p.y;
      }
    }
    project.relations.addAll(_relations);
    return ImportResult(project, notes, dialect);
  }

  final _relations = <RelationModel>[];

  // ---------- แยกคำสั่ง ----------

  static const _starters = {'CREATE', 'DROP', 'INSERT', 'EXEC', 'EXECUTE'};

  List<List<Tok>> _split(List<Tok> toks) {
    final out = <List<Tok>>[];
    var cur = <Tok>[];
    var depth = 0;
    void flush() {
      if (cur.isNotEmpty) out.add(cur);
      cur = [];
      depth = 0;
    }

    for (var k = 0; k < toks.length; k++) {
      final t = toks[k];
      final prevLine = k > 0 ? toks[k - 1].line : -1;
      final nextLine = k + 1 < toks.length ? toks[k + 1].line : -1;

      // GO (SQL Server) ต้องอยู่บรรทัดของตัวเองคนเดียว
      if (t.isWord('GO') && t.line != prevLine && t.line != nextLine) {
        flush();
        continue;
      }
      if (t.isSym(';') && depth == 0) {
        flush();
        continue;
      }
      if (t.isSym('(')) depth++;
      if (t.isSym(')') && depth > 0) depth--;

      // สคริปต์ที่ไม่มี ; : คำสั่งใหม่ขึ้นต้นบรรทัดนอกวงเล็บ
      if (cur.isNotEmpty && depth == 0 && t.line != prevLine && t.kind == Tk.word) {
        final u = t.text.toUpperCase();
        final alterNew = u == 'ALTER' && !cur.first.isWord('ALTER');
        if (_starters.contains(u) || alterNew) flush();
      }
      cur.add(t);
    }
    flush();
    return out;
  }

  // ---------- คำสั่ง ----------

  void _statement(List<Tok> st) {
    final c = _Cur(st);
    final first = c.next();
    final line = first.line;
    final w = first.kind == Tk.word ? first.text.toUpperCase() : '';

    if (w == 'CREATE') {
      // ข้ามตัวขยาย: OR REPLACE, TEMP, UNIQUE, CLUSTERED ฯลฯ จนเจอ TABLE / INDEX
      var unique = false;
      while (!c.done) {
        if (c.isWord('TABLE')) {
          c.i++;
          return _createTable(c, line);
        }
        if (c.isWord('INDEX')) {
          c.i++;
          return _createIndex(c, line, unique);
        }
        if (c.isWord('UNIQUE')) unique = true;
        if (c.isWord('VIEW') ||
            c.isWord('TRIGGER') ||
            c.isWord('SEQUENCE') ||
            c.isWord('FUNCTION') ||
            c.isWord('PROCEDURE') ||
            c.isWord('DATABASE') ||
            c.isWord('SCHEMA') ||
            c.isWord('TYPE') ||
            c.isWord('EXTENSION')) {
          break;
        }
        c.i++;
      }
      return _skip(st, 'CREATE ${c.done ? '' : c.at(0)!.text.toUpperCase()}');
    }
    if (w == 'ALTER' && c.isWord('TABLE')) {
      c.i++;
      return _alterTable(c, line);
    }
    if (w == 'COMMENT' && c.isWord('ON')) {
      c.i++;
      return _commentOn(c, line);
    }
    if ((w == 'EXEC' || w == 'EXECUTE') && c.at(0)?.text.toLowerCase() == 'sp_addextendedproperty') {
      c.i++;
      return _extendedProperty(c, line);
    }
    _skip(st, w.isEmpty ? '(ไม่ทราบ)' : (w == 'ALTER' || w == 'DROP' ? '$w ${c.at(0)?.text.toUpperCase() ?? ''}'.trim() : w));
  }

  void _skip(List<Tok> st, String what) {
    // คำสั่งที่พบบ่อยในไฟล์ dump ไม่ต้องเตือนทีละคำสั่ง รวมเป็นยอดท้ายรายงาน
    skipped[what] = (skipped[what] ?? 0) + 1;
  }

  // ---------- ชื่อและรายการ ----------

  /// ชื่อวัตถุ อาจมี schema นำหน้า (a.b.c) — เอาส่วนสุดท้าย
  String _objectName(_Cur c) {
    final t = c.next();
    if (!t.isName) throw _ParseError('คาดว่าเป็นชื่อ แต่พบ "${t.text}"');
    var name = t.text;
    while (c.isSym('.')) {
      c.i++;
      final n = c.next();
      if (!n.isName) throw _ParseError('ชื่อหลังจุดไม่ถูกต้อง');
      name = n.text;
    }
    return name;
  }

  List<Tok> _balanced(_Cur c) {
    if (!c.isSym('(')) throw const _ParseError('คาดว่าเป็น (');
    c.i++;
    var depth = 1;
    final start = c.i;
    while (!c.done) {
      final x = c.t[c.i];
      if (x.isSym('(')) depth++;
      if (x.isSym(')')) {
        depth--;
        if (depth == 0) {
          final inner = c.t.sublist(start, c.i);
          c.i++;
          return inner;
        }
      }
      c.i++;
    }
    throw const _ParseError('วงเล็บไม่ครบคู่');
  }

  List<List<Tok>> _splitTop(List<Tok> toks) {
    final out = <List<Tok>>[];
    var cur = <Tok>[];
    var depth = 0;
    for (final t in toks) {
      if (t.isSym('(')) depth++;
      if (t.isSym(')')) depth--;
      if (t.isSym(',') && depth == 0) {
        if (cur.isNotEmpty) out.add(cur);
        cur = [];
        continue;
      }
      cur.add(t);
    }
    if (cur.isNotEmpty) out.add(cur);
    return out;
  }

  /// ( col [(n)] [ASC|DESC] [AUTOINCREMENT], ... ) — name เป็น null ถ้าเป็น expression
  List<({String? name, bool ai})> _colList(_Cur c) {
    final inner = _balanced(c);
    final out = <({String? name, bool ai})>[];
    for (final part in _splitTop(inner)) {
      final p = _Cur(part);
      final t = p.next();
      if (!t.isName) {
        out.add((name: null, ai: false));
        continue;
      }
      var valid = true;
      var ai = false;
      if (p.isSym('(')) {
        // t(...) = เรียกฟังก์ชัน (expression); คอลัมน์ที่มี prefix length มักเป็น (10) ตัวเลขล้วน
        final inside = _balanced(p);
        valid = inside.length == 1 && inside.first.kind == Tk.number;
      }
      if (p.isSym('.')) valid = false;
      while (!p.done) {
        if (p.isWord('AUTOINCREMENT')) ai = true;
        p.i++;
      }
      out.add((name: valid ? t.text : null, ai: ai));
    }
    return out;
  }

  // ---------- CREATE TABLE ----------

  void _createTable(_Cur c, int line) {
    c.eatWords(['IF', 'NOT', 'EXISTS']);
    final name = _objectName(c);
    if (!c.isSym('(')) {
      note(line, 'CREATE TABLE $name ... AS/LIKE ไม่รองรับ — ข้าม');
      return;
    }
    if (byName.containsKey(name.toLowerCase())) {
      note(line, 'ตาราง $name ถูกสร้างซ้ำ — ใช้ครั้งแรก ข้ามครั้งนี้');
      return;
    }
    final body = _balanced(c);
    final t = TableModel(id: id('t'), name: name);
    tables.add(t);
    byName[name.toLowerCase()] = t;

    for (final item in _splitTop(body)) {
      try {
        _tableItem(t, item, line);
      } on _ParseError catch (e) {
        note(item.first.line, '$name: อ่านรายการ "${item.first.text}…" ไม่ได้ (${e.message}) — ข้าม');
      }
    }

    // ตัวเลือกท้ายตาราง: COMMENT='...'
    while (!c.done) {
      if (c.isWord('COMMENT')) {
        c.i++;
        c.eatSym('=');
        final s = c.at(0);
        if (s != null && s.kind == Tk.string) {
          t.comment = s.text;
          c.i++;
        }
        continue;
      }
      c.i++;
    }
    if (t.columns.isEmpty) note(line, 'ตาราง $name ไม่มีคอลัมน์ที่อ่านได้');
  }

  void _tableItem(TableModel t, List<Tok> item, int line) {
    final c = _Cur(item);
    final f = c.at(0)!;
    if (f.kind == Tk.word) {
      final u = f.text.toUpperCase();
      if (u == 'CONSTRAINT') {
        c.i++;
        final cname = c.next().text;
        return _constraint(t, c, cname, line);
      }
      if (const {'PRIMARY', 'UNIQUE', 'FOREIGN', 'CHECK'}.contains(u)) return _constraint(t, c, null, line);
      if (u == 'KEY' || u == 'INDEX') {
        final n1 = c.at(1);
        final looksIndex = n1 != null && (n1.isSym('(') || (n1.isName && c.isSym('(', 2)));
        if (looksIndex) return _constraint(t, c, null, line);
      }
      if (u == 'FULLTEXT' || u == 'SPATIAL') {
        note(line, '${t.name}: ข้าม $u INDEX');
        return;
      }
      if (u == 'EXCLUDE' || u == 'LIKE' || u == 'PERIOD') {
        note(line, '${t.name}: ข้ามข้อกำหนด $u');
        return;
      }
    }
    _column(t, c, line);
  }

  void _constraint(TableModel t, _Cur c, String? cname, int line) {
    if (c.eatWord('CHECK')) return; // ไม่เก็บ CHECK
    if (c.eatWords(['PRIMARY', 'KEY'])) {
      c.eatWord('CLUSTERED');
      c.eatWord('NONCLUSTERED');
      if (c.at(0)?.isName == true && c.isSym('(', 1)) c.i++; // ชื่อ
      for (final col in _colList(c)) {
        final m = _findCol(t, col.name);
        if (m == null) {
          note(line, '${t.name}: PRIMARY KEY ชี้คอลัมน์ "${col.name}" ที่ไม่มี');
          continue;
        }
        m.isPrimaryKey = true;
        m.notNull = true;
        if (col.ai) m.autoIncrement = true;
      }
      return;
    }
    if (c.eatWord('UNIQUE')) {
      if (!c.eatWord('KEY')) c.eatWord('INDEX');
      c.eatWord('CLUSTERED');
      c.eatWord('NONCLUSTERED');
      String? iname = cname;
      if (c.at(0)?.isName == true && c.isSym('(', 1)) iname = c.next().text;
      _unique(t, _colList(c), iname, line);
      return;
    }
    if (c.eatWords(['FOREIGN', 'KEY'])) {
      if (c.at(0)?.isName == true && c.isSym('(', 1)) c.i++;
      final cols = _colList(c).map((x) => x.name).toList();
      if (!c.eatWord('REFERENCES')) throw const _ParseError('FOREIGN KEY ไม่มี REFERENCES');
      final ref = _references(c);
      _queueFk(line, t.name, cols, ref, cname);
      return;
    }
    if (c.isWord('KEY') || c.isWord('INDEX')) {
      c.i++;
      String? iname;
      if (c.at(0)?.isName == true && c.isSym('(', 1)) iname = c.next().text;
      _addIndex(t, _colList(c), iname, false, line);
      return;
    }
    throw _ParseError('ข้อกำหนด "${c.at(0)?.text}" ไม่รองรับ');
  }

  void _unique(TableModel t, List<({String? name, bool ai})> cols, String? iname, int line) {
    if (cols.length == 1 && cols.first.name != null) {
      final m = _findCol(t, cols.first.name);
      if (m != null) {
        m.unique = true;
        return;
      }
    }
    _addIndex(t, cols, iname, true, line);
  }

  void _addIndex(TableModel t, List<({String? name, bool ai})> cols, String? iname, bool unique, int line) {
    final ids = <String>[];
    for (final col in cols) {
      final m = _findCol(t, col.name);
      if (m == null) {
        note(line, '${t.name}: INDEX ${iname ?? ''} ใช้ expression หรือคอลัมน์ที่ไม่มี — ข้าม');
        return;
      }
      ids.add(m.id);
    }
    if (ids.isEmpty) return;
    final name = iname ?? '${unique ? 'ux' : 'idx'}_${t.name}_${cols.map((x) => x.name).join('_')}';
    t.indexes.add(IndexModel(id: id('i'), name: name, columnIds: ids, unique: unique));
  }

  ColumnModel? _findCol(TableModel t, String? name) {
    if (name == null) return null;
    final l = name.toLowerCase();
    for (final c in t.columns) {
      if (c.name.toLowerCase() == l) return c;
    }
    return null;
  }

  // ---------- คอลัมน์ ----------

  void _column(TableModel t, _Cur c, int line) {
    final nameTok = c.next();
    if (!nameTok.isName) throw _ParseError('ชื่อคอลัมน์ไม่ถูกต้อง "${nameTok.text}"');
    final col = ColumnModel(id: id('c'), name: nameTok.text);
    final ty = _type(c, line, t.name, col.name);
    col.type = ty.type;
    col.length = ty.length;
    col.scale = ty.scale;
    if (ty.ai) {
      col.autoIncrement = true;
      col.notNull = true;
    }

    _Ref? inlineRef;
    while (!c.done) {
      if (c.eatWord('CONSTRAINT')) {
        c.next();
      } else if (c.eatWords(['NOT', 'NULL'])) {
        col.notNull = true;
      } else if (c.eatWord('NULL')) {
        // อนุญาต NULL อยู่แล้ว
      } else if (c.eatWord('DEFAULT')) {
        final v = _readDefault(c);
        if (v == null) {
          // DEFAULT NULL = ไม่มีค่าเริ่มต้น
        } else if (v.toLowerCase().startsWith('nextval(')) {
          if (isIntType(col.type)) col.autoIncrement = true; // serial ที่ dump ออกมาเป็น nextval
        } else {
          col.defaultValue = v;
        }
      } else if (c.eatWords(['PRIMARY', 'KEY'])) {
        col.isPrimaryKey = true;
        col.notNull = true;
        c.eatWord('CLUSTERED');
        c.eatWord('NONCLUSTERED');
        c.eatWord('ASC');
        c.eatWord('DESC');
      } else if (c.eatWord('UNIQUE')) {
        c.eatWord('KEY');
        col.unique = true;
      } else if (c.eatWord('AUTO_INCREMENT') || c.eatWord('AUTOINCREMENT')) {
        col.autoIncrement = true;
      } else if (c.eatWord('IDENTITY')) {
        col.autoIncrement = true;
        if (c.isSym('(')) _balanced(c);
      } else if (c.eatWord('GENERATED')) {
        while (c.isWord('ALWAYS') || c.isWord('BY') || c.isWord('DEFAULT') || c.isWord('AS')) {
          c.i++;
        }
        if (c.eatWord('IDENTITY')) {
          col.autoIncrement = true;
          if (c.isSym('(')) _balanced(c);
        } else {
          note(line, '${t.name}.${col.name}: คอลัมน์ที่คำนวณจากสูตรไม่รองรับ — เก็บเป็นคอลัมน์ปกติ');
          if (c.isSym('(')) _balanced(c);
          c.eatWord('STORED');
          c.eatWord('VIRTUAL');
        }
      } else if (c.eatWord('REFERENCES')) {
        inlineRef = _references(c);
      } else if (c.eatWord('CHECK')) {
        if (c.isSym('(')) _balanced(c);
      } else if (c.eatWord('COMMENT')) {
        c.eatSym('=');
        final s = c.at(0);
        if (s != null && s.kind == Tk.string) {
          col.comment = s.text;
          c.i++;
        }
      } else if (c.eatWord('COLLATE')) {
        c.next();
      } else if (c.eatWords(['CHARACTER', 'SET']) || c.eatWord('CHARSET')) {
        c.next();
      } else if (c.eatWord('ON')) {
        // ON UPDATE CURRENT_TIMESTAMP (MySQL)
        c.eatWord('UPDATE');
        if (!c.done) c.i++;
        if (c.isSym('(')) _balanced(c);
      } else {
        c.i++; // คำที่ไม่รู้จัก (VISIBLE, STORED ...) ข้าม
      }
    }
    if (_findCol(t, col.name) != null) {
      note(line, '${t.name}: คอลัมน์ "${col.name}" ซ้ำ — ข้ามตัวหลัง');
      return;
    }
    t.columns.add(col);
    if (inlineRef != null) _queueFk(line, t.name, [col.name], inlineRef, null);
  }

  bool isIntType(DataType t) => t == DataType.integer || t == DataType.bigint || t == DataType.smallint;

  /// อ่านค่า DEFAULT -> ข้อความ (ถอด quote/วงเล็บนอก), null = NULL
  String? _readDefault(_Cur c) {
    final t = c.next();
    String? value;
    if (t.kind == Tk.string) {
      value = t.text;
    } else if (t.isSym('-') || t.isSym('+')) {
      final n = c.next();
      value = '${t.text}${n.text}';
    } else if (t.kind == Tk.number) {
      value = t.text;
    } else if (t.isSym('(')) {
      c.i--;
      final inner = _stripParens(_balanced(c));
      if (inner.isEmpty) {
        value = '';
      } else if (inner.length == 1 && (inner.first.kind == Tk.string || inner.first.kind == Tk.number)) {
        value = inner.first.text;
      } else {
        value = src.substring(inner.first.start, inner.last.end); // เช่น uuid()
      }
    } else if (t.kind == Tk.word || t.kind == Tk.ident) {
      if (c.isSym('(')) {
        _balanced(c);
        value = src.substring(t.start, c.t[c.i - 1].end); // เช่น now(), nextval('s'::regclass)
      } else {
        value = t.text;
        if (t.kind == Tk.word && t.text.toUpperCase() == 'NULL') value = null;
      }
    } else {
      throw _ParseError('ค่า DEFAULT ไม่ถูกต้อง "${t.text}"');
    }
    // PostgreSQL cast: 'x'::character varying
    while (c.isSym('::')) {
      c.i++;
      while (!c.done && c.at(0)!.kind == Tk.word && !_isColumnKeyword(c.at(0)!)) {
        c.i++;
        if (c.isSym('(')) _balanced(c);
      }
      while (c.isSym('[') && c.isSym(']', 1)) {
        c.i += 2;
      }
    }
    return value;
  }

  /// ถอดวงเล็บชั้นนอกที่ครอบทั้งนิพจน์ซ้ำ ๆ เช่น ((0)) -> 0
  List<Tok> _stripParens(List<Tok> t) {
    while (t.length >= 2 && t.first.isSym('(') && t.last.isSym(')')) {
      var depth = 0;
      var wraps = true;
      for (var k = 0; k < t.length; k++) {
        if (t[k].isSym('(')) depth++;
        if (t[k].isSym(')')) depth--;
        if (depth == 0 && k < t.length - 1) {
          wraps = false; // วงเล็บแรกปิดก่อนจบ เช่น (a)+(b)
          break;
        }
      }
      if (!wraps) break;
      t = t.sublist(1, t.length - 1);
    }
    return t;
  }

  static const _colKeywords = {
    'NOT', 'NULL', 'DEFAULT', 'PRIMARY', 'UNIQUE', 'REFERENCES', 'CHECK', 'COMMENT', 'COLLATE',
    'CONSTRAINT', 'AUTO_INCREMENT', 'AUTOINCREMENT', 'GENERATED', 'ON', 'IDENTITY', //
  };
  bool _isColumnKeyword(Tok t) => _colKeywords.contains(t.text.toUpperCase());

  // ---------- ชนิดข้อมูล ----------

  ({DataType type, int? length, int? scale, bool ai}) _type(_Cur c, int line, String table, String col) {
    final first = c.next();
    if (!first.isName) throw _ParseError('คาดว่าเป็นชนิดข้อมูล แต่พบ "${first.text}"');
    var base = first.text.toUpperCase();

    if (base == 'DOUBLE' && c.isWord('PRECISION')) {
      c.i++;
      base = 'DOUBLE';
    } else if ((base == 'CHARACTER' || base == 'CHAR') && c.isWord('VARYING')) {
      c.i++;
      base = 'VARCHAR';
    } else if (base == 'NATIONAL' && !c.done) {
      base = c.next().text.toUpperCase();
      if (c.eatWord('VARYING')) base = 'VARCHAR';
    }
    while (c.isSym('.')) {
      // ชนิดมี schema เช่น public.citext
      c.i++;
      base = c.next().text.toUpperCase();
    }

    final params = <int?>[];
    var isMax = false;
    if (c.isSym('(')) {
      for (final part in _splitTop(_balanced(c))) {
        final v = part.isNotEmpty ? part.first : null;
        if (v != null && v.kind == Tk.number) {
          params.add(int.tryParse(v.text));
        } else if (v != null && v.isWord('MAX')) {
          isMax = true;
        }
      }
    }

    bool? tz;
    if (c.eatWords(['WITH', 'TIME', 'ZONE'])) tz = true;
    if (c.eatWords(['WITHOUT', 'TIME', 'ZONE'])) tz = false;
    while (c.isSym('[') && c.isSym(']', 1)) {
      c.i += 2;
      note(line, '$table.$col: ชนิด array ไม่รองรับ — เก็บเป็น TEXT');
      base = 'TEXT';
    }
    // ตัวขยายชนิดที่ไม่กระทบโมเดล
    while (c.isWord('UNSIGNED') || c.isWord('SIGNED') || c.isWord('ZEROFILL')) {
      c.i++;
    }

    int? p0 = params.isNotEmpty ? params[0] : null;
    int? p1 = params.length > 1 ? params[1] : null;

    ({DataType type, int? length, int? scale, bool ai}) r(DataType t,
            {int? length, int? scale, bool ai = false}) =>
        (type: t, length: length, scale: scale, ai: ai);

    switch (base) {
      case 'INT':
      case 'INTEGER':
      case 'MEDIUMINT':
      case 'INT4':
        return r(DataType.integer);
      case 'BIGINT':
      case 'INT8':
        return r(DataType.bigint);
      case 'SMALLINT':
      case 'INT2':
        return r(DataType.smallint);
      case 'TINYINT':
        return p0 == 1 ? r(DataType.boolean) : r(DataType.smallint);
      case 'SERIAL':
      case 'SERIAL4':
        return r(DataType.integer, ai: true);
      case 'BIGSERIAL':
      case 'SERIAL8':
        return r(DataType.bigint, ai: true);
      case 'SMALLSERIAL':
      case 'SERIAL2':
        return r(DataType.smallint, ai: true);
      case 'CHAR':
      case 'NCHAR':
      case 'CHARACTER':
        if (base != 'NCHAR' && p0 == 36) return r(DataType.uuid);
        return r(DataType.varchar, length: p0 ?? 1);
      case 'VARCHAR':
      case 'NVARCHAR':
      case 'VARCHAR2':
      case 'NVARCHAR2':
      case 'BPCHAR':
      case 'STRING':
        if (isMax) return r(DataType.text);
        return r(DataType.varchar, length: p0);
      case 'TEXT':
      case 'LONGTEXT':
      case 'MEDIUMTEXT':
      case 'TINYTEXT':
      case 'NTEXT':
      case 'CLOB':
      case 'CITEXT':
        return r(DataType.text);
      case 'DECIMAL':
      case 'DEC':
      case 'NUMERIC':
      case 'NUMBER':
      case 'FIXED':
        return r(DataType.decimal, length: p0, scale: p1);
      case 'MONEY':
        return r(DataType.decimal, length: 19, scale: 4);
      case 'FLOAT':
      case 'DOUBLE':
      case 'REAL':
      case 'FLOAT4':
      case 'FLOAT8':
        return r(DataType.float);
      case 'BOOLEAN':
      case 'BOOL':
      case 'BIT':
        return r(DataType.boolean);
      case 'DATE':
        return r(DataType.date);
      case 'DATETIME':
      case 'DATETIME2':
      case 'SMALLDATETIME':
        return r(DataType.datetime);
      case 'TIMESTAMP':
        if (tz == true) return r(DataType.timestamp);
        if (tz == false || dialect == Dialect.postgres) return r(DataType.datetime);
        return r(DataType.timestamp);
      case 'TIMESTAMPTZ':
        return r(DataType.timestamp);
      case 'BLOB':
      case 'TINYBLOB':
      case 'MEDIUMBLOB':
      case 'LONGBLOB':
      case 'BYTEA':
      case 'VARBINARY':
      case 'BINARY':
      case 'IMAGE':
        return r(DataType.blob);
      case 'UUID':
      case 'UNIQUEIDENTIFIER':
        return r(DataType.uuid);
      case 'JSON':
      case 'JSONB':
        return r(DataType.json);
    }
    note(line, '$table.$col: ไม่รู้จักชนิด "${first.text}" — เก็บเป็น TEXT');
    return r(DataType.text);
  }

  // ---------- REFERENCES / FK ----------

  _Ref _references(_Cur c) {
    final table = _objectName(c);
    var cols = <String>[];
    if (c.isSym('(')) {
      cols = _colList(c).map((x) => x.name ?? '').where((x) => x.isNotEmpty).toList();
    }
    var onDelete = RefAction.noAction;
    var onUpdate = RefAction.noAction;
    while (!c.done) {
      if (c.eatWord('ON')) {
        final isDelete = c.isWord('DELETE');
        if (!isDelete && !c.isWord('UPDATE')) break;
        c.i++;
        final a = _action(c);
        if (isDelete) {
          onDelete = a;
        } else {
          onUpdate = a;
        }
      } else if (c.eatWord('MATCH')) {
        c.next();
      } else if (c.isWord('NOT') && c.isWord('DEFERRABLE', 1)) {
        c.i += 2; // NOT DEFERRABLE (ไม่ชนกับ NOT NULL ที่ตามหลัง REFERENCES)
      } else if (c.eatWord('DEFERRABLE')) {
        // ไม่กระทบโมเดล
      } else if (c.eatWord('INITIALLY')) {
        c.next(); // DEFERRED | IMMEDIATE
      } else {
        break;
      }
    }
    return _Ref(table, cols, onDelete, onUpdate);
  }

  RefAction _action(_Cur c) {
    if (c.eatWord('CASCADE')) return RefAction.cascade;
    if (c.eatWord('RESTRICT')) return RefAction.restrict;
    if (c.eatWords(['NO', 'ACTION'])) return RefAction.noAction;
    if (c.eatWords(['SET', 'NULL'])) return RefAction.setNull;
    if (c.eatWords(['SET', 'DEFAULT'])) {
      note(c.at(-1)?.line ?? 0, 'SET DEFAULT ไม่รองรับ — ใช้ NO ACTION แทน');
      return RefAction.noAction;
    }
    throw const _ParseError('action ของ FK ไม่ถูกต้อง');
  }

  void _queueFk(int line, String child, List<String?> cols, _Ref ref, String? name) {
    pending.add(_PendingFk(
      line,
      child,
      [for (final c in cols) c ?? ''],
      ref.table,
      ref.cols,
      ref.onDelete,
      ref.onUpdate,
      name,
    ));
  }

  void _resolveFks() {
    for (final p in pending) {
      final child = byName[p.childTable.toLowerCase()];
      final parent = byName[p.parentTable.toLowerCase()];
      if (child == null) continue;
      if (parent == null) {
        note(p.line, 'FK ${p.childTable} → ${p.parentTable}: ไม่พบตาราง ${p.parentTable} ในไฟล์ — ข้าม');
        continue;
      }
      var parentCols = p.parentCols;
      if (parentCols.isEmpty) {
        parentCols = [for (final c in parent.columns) if (c.isPrimaryKey) c.name];
      }
      if (parentCols.length != p.childCols.length || parentCols.isEmpty) {
        note(p.line, 'FK ${p.childTable} → ${p.parentTable}: จำนวนคอลัมน์ไม่ตรงกัน — ข้าม');
        continue;
      }
      if (p.childCols.length > 1) {
        note(p.line, 'FK หลายคอลัมน์ ${p.childTable} → ${p.parentTable}: แยกเป็น FK ทีละคอลัมน์');
      }
      for (var k = 0; k < p.childCols.length; k++) {
        final cc = _findCol(child, p.childCols[k]);
        final pc = _findCol(parent, parentCols[k]);
        if (cc == null || pc == null) {
          note(p.line, 'FK ${p.childTable}.${p.childCols[k]} → ${p.parentTable}.${parentCols[k]}: ไม่พบคอลัมน์ — ข้าม');
          continue;
        }
        final dup = _relations.any((r) =>
            r.fromTableId == child.id &&
            r.fromColumnId == cc.id &&
            r.toTableId == parent.id &&
            r.toColumnId == pc.id);
        if (dup) continue;
        _relations.add(RelationModel(
          id: id('r'),
          fromTableId: child.id,
          fromColumnId: cc.id,
          toTableId: parent.id,
          toColumnId: pc.id,
          onDelete: p.onDelete,
          onUpdate: p.onUpdate,
          name: p.childCols.length == 1 ? p.name : null,
        ));
      }
    }
  }

  // ---------- ALTER TABLE ----------

  void _alterTable(_Cur c, int line) {
    c.eatWord('ONLY');
    c.eatWords(['IF', 'EXISTS']);
    final name = _objectName(c);
    final t = byName[name.toLowerCase()];
    // SSMS: ALTER TABLE x WITH CHECK ADD CONSTRAINT ...
    if (!c.eatWords(['WITH', 'CHECK'])) c.eatWords(['WITH', 'NOCHECK']);
    final rest = c.t.sublist(c.i);
    for (final action in _splitTop(rest)) {
      final a = _Cur(action);
      if (!a.eatWord('ADD')) {
        _skip(action, 'ALTER TABLE ${action.first.text.toUpperCase()}');
        continue;
      }
      if (t == null) {
        note(line, 'ALTER TABLE $name: ไม่พบตาราง $name ในไฟล์ — ข้าม');
        return;
      }
      try {
        if (a.isWord('CONSTRAINT')) {
          a.i++;
          final cname = a.next().text;
          _constraint(t, a, cname, line);
        } else if (const {'PRIMARY', 'UNIQUE', 'FOREIGN', 'CHECK', 'KEY', 'INDEX'}.contains(a.at(0)?.text.toUpperCase())) {
          _constraint(t, a, null, line);
        } else {
          a.eatWord('COLUMN');
          a.eatWords(['IF', 'NOT', 'EXISTS']);
          _column(t, a, line);
        }
      } on _ParseError catch (e) {
        note(line, 'ALTER TABLE $name: อ่านไม่ได้ (${e.message}) — ข้าม');
      }
    }
  }

  // ---------- CREATE INDEX ----------

  void _createIndex(_Cur c, int line, bool unique) {
    c.eatWord('CONCURRENTLY');
    c.eatWords(['IF', 'NOT', 'EXISTS']);
    String? iname;
    if (!c.isWord('ON')) iname = _objectName(c);
    if (!c.eatWord('ON')) throw const _ParseError('CREATE INDEX ไม่มี ON');
    c.eatWord('ONLY');
    final tname = _objectName(c);
    final t = byName[tname.toLowerCase()];
    if (c.eatWord('USING')) c.next();
    final cols = _colList(c);
    if (t == null) {
      note(line, 'INDEX ${iname ?? ''}: ไม่พบตาราง $tname ในไฟล์ — ข้าม');
      return;
    }
    if (unique && cols.length == 1 && iname == null) {
      _unique(t, cols, null, line);
    } else {
      _addIndex(t, cols, iname, unique, line);
    }
  }

  // ---------- COMMENT ----------

  void _commentOn(_Cur c, int line) {
    final isTable = c.isWord('TABLE');
    final isColumn = c.isWord('COLUMN');
    if (!isTable && !isColumn) {
      _skip(c.t, 'COMMENT ON ${c.at(0)?.text.toUpperCase() ?? ''}');
      return;
    }
    c.i++;
    final parts = <String>[];
    do {
      parts.add(c.next().text);
    } while (c.eatSym('.'));
    if (!c.eatWord('IS')) throw const _ParseError('COMMENT ON ไม่มี IS');
    final s = c.next();
    final text = s.kind == Tk.string ? s.text : '';
    if (isTable) {
      final t = byName[parts.last.toLowerCase()];
      if (t != null) t.comment = text;
    } else if (parts.length >= 2) {
      final t = byName[parts[parts.length - 2].toLowerCase()];
      final col = t == null ? null : _findCol(t, parts.last);
      if (col != null) col.comment = text;
    }
  }

  void _extendedProperty(_Cur c, int line) {
    final strs = [for (final t in c.t.sublist(c.i)) if (t.kind == Tk.string) t.text];
    // MS_Description, <text>, SCHEMA, dbo, TABLE, <name> [, COLUMN, <name>]
    if (strs.length < 6 || strs[0].toLowerCase() != 'ms_description') return;
    final t = byName[strs[5].toLowerCase()];
    if (t == null) return;
    if (strs.length >= 8 && strs[6].toUpperCase() == 'COLUMN') {
      _findCol(t, strs[7])?.comment = strs[1];
    } else {
      t.comment = strs[1];
    }
  }
}
