import 'package:nsl_dev/core/models/column_model.dart';
import 'package:nsl_dev/core/models/enums.dart';
import 'package:nsl_dev/core/models/index_model.dart';
import 'package:nsl_dev/core/models/project.dart';
import 'package:nsl_dev/core/models/relation_model.dart';
import 'package:nsl_dev/core/models/table_model.dart';

/// ข้อมูลทดสอบกลางของชุดทดสอบ diff/migration
ColumnModel col(String id, String name,
        {DataType type = DataType.integer,
        bool pk = false,
        bool nn = false,
        bool uq = false,
        bool ai = false,
        int? len,
        int? scale,
        String? def,
        String comment = ''}) =>
    ColumnModel(
        id: id,
        name: name,
        type: type,
        isPrimaryKey: pk,
        notNull: nn,
        unique: uq,
        autoIncrement: ai,
        length: len,
        scale: scale,
        defaultValue: def,
        comment: comment);

Project base([Dialect d = Dialect.mysql]) => Project(name: 'shop', dialect: d, tables: [
      TableModel(id: 'tu', name: 'users', columns: [
        col('u1', 'id', pk: true, ai: true),
        col('u2', 'email', type: DataType.varchar, len: 255, nn: true, uq: true),
        col('u3', 'name', type: DataType.varchar, len: 100),
        col('u4', 'age'),
      ]),
      TableModel(id: 'to', name: 'orders', columns: [
        col('o1', 'id', pk: true, ai: true),
        col('o2', 'user_id', nn: true),
        col('o3', 'total', type: DataType.decimal, len: 10, scale: 2, nn: true, def: '0'),
        col('o4', 'note', type: DataType.text),
      ], indexes: [
        IndexModel(id: 'i1', name: 'idx_orders_user', columnIds: ['o2']),
      ]),
    ], relations: [
      RelationModel(
          id: 'r1',
          fromTableId: 'to',
          fromColumnId: 'o2',
          toTableId: 'tu',
          toColumnId: 'u1',
          onDelete: RefAction.cascade),
    ]);

Project clone(Project p) => Project.fromJson(p.toJson());
TableModel tb(Project p, String id) => p.tableById(id)!;
ColumnModel cl(Project p, String t, String c) => tb(p, t).columnById(c)!;
