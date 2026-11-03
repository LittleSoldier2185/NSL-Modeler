import 'column_model.dart';
import 'index_model.dart';

class TableModel {
  TableModel({
    required this.id,
    required this.name,
    this.comment = '',
    this.x = 0,
    this.y = 0,
    this.width = 220,
    List<ColumnModel>? columns,
    List<IndexModel>? indexes,
  })  : columns = columns ?? [],
        indexes = indexes ?? [];

  String id;
  String name;
  String comment;
  double x;
  double y;
  double width;
  List<ColumnModel> columns;
  List<IndexModel> indexes;

  ColumnModel? columnById(String id) {
    for (final c in columns) {
      if (c.id == id) return c;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (comment.isNotEmpty) 'comment': comment,
        'x': x,
        'y': y,
        'width': width,
        'columns': columns.map((c) => c.toJson()).toList(),
        'indexes': indexes.map((i) => i.toJson()).toList(),
      };

  factory TableModel.fromJson(Map<String, dynamic> j) => TableModel(
        id: j['id'] as String,
        name: j['name'] as String,
        comment: j['comment'] as String? ?? '',
        x: (j['x'] as num? ?? 0).toDouble(),
        y: (j['y'] as num? ?? 0).toDouble(),
        width: (j['width'] as num? ?? 220).toDouble(),
        columns: (j['columns'] as List? ?? [])
            .map((e) => ColumnModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        indexes: (j['indexes'] as List? ?? [])
            .map((e) => IndexModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
