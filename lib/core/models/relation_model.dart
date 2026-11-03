import 'color_utils.dart';
import 'enums.dart';

/// FK: fromTable.fromColumn (ลูก) -> toTable.toColumn (แม่)
class RelationModel {
  RelationModel({
    required this.id,
    required this.fromTableId,
    required this.fromColumnId,
    required this.toTableId,
    required this.toColumnId,
    this.onDelete = RefAction.noAction,
    this.onUpdate = RefAction.noAction,
    this.name,
    this.color,
  });

  /// สีเส้นของความสัมพันธ์นี้ (ARGB) — null = ใช้สีเส้นเริ่มต้นของโปรเจกต์/ธีม
  int? color;

  String id;
  String fromTableId;
  String fromColumnId;
  String toTableId;
  String toColumnId;
  RefAction onDelete;
  RefAction onUpdate;
  String? name;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromTable': fromTableId,
        'fromColumn': fromColumnId,
        'toTable': toTableId,
        'toColumn': toColumnId,
        'onDelete': onDelete.name,
        'onUpdate': onUpdate.name,
        if (name != null) 'name': name,
        if (color != null) 'color': color,
      };

  factory RelationModel.fromJson(Map<String, dynamic> j) => RelationModel(
        id: j['id'] as String,
        fromTableId: j['fromTable'] as String,
        fromColumnId: j['fromColumn'] as String,
        toTableId: j['toTable'] as String,
        toColumnId: j['toColumn'] as String,
        onDelete: RefAction.values.byName(j['onDelete'] as String? ?? 'noAction'),
        onUpdate: RefAction.values.byName(j['onUpdate'] as String? ?? 'noAction'),
        name: j['name'] as String?,
        color: parseArgb(j['color']),
      );
}
