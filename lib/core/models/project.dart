import 'enums.dart';
import 'note_model.dart';
import 'relation_model.dart';
import 'table_model.dart';

class Project {
  Project({
    this.name = 'untitled',
    this.dialect = Dialect.mysql,
    List<TableModel>? tables,
    List<RelationModel>? relations,
    List<NoteModel>? notes,
  })  : tables = tables ?? [],
        relations = relations ?? [],
        notes = notes ?? [];

  String name;
  Dialect dialect;
  List<TableModel> tables;
  List<RelationModel> relations;
  List<NoteModel> notes;

  TableModel? tableById(String id) {
    for (final t in tables) {
      if (t.id == id) return t;
    }
    return null;
  }

  static const formatVersion = 1;

  Map<String, dynamic> toJson() => {
        'format': 'nsl-erd',
        'version': formatVersion,
        'name': name,
        'dialect': dialect.name,
        'tables': tables.map((t) => t.toJson()).toList(),
        'relations': relations.map((r) => r.toJson()).toList(),
        'notes': notes.map((n) => n.toJson()).toList(),
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        name: j['name'] as String? ?? 'untitled',
        dialect: Dialect.values.byName(j['dialect'] as String? ?? 'mysql'),
        tables: (j['tables'] as List? ?? [])
            .map((e) => TableModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        relations: (j['relations'] as List? ?? [])
            .map((e) => RelationModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        notes: (j['notes'] as List? ?? [])
            .map((e) => NoteModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
