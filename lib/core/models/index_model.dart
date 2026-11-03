class IndexModel {
  IndexModel({
    required this.id,
    required this.name,
    required this.columnIds,
    this.unique = false,
  });

  String id;
  String name;
  List<String> columnIds;
  bool unique;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'columns': columnIds, 'unique': unique};

  factory IndexModel.fromJson(Map<String, dynamic> j) => IndexModel(
        id: j['id'] as String,
        name: j['name'] as String,
        columnIds: (j['columns'] as List).cast<String>().toList(),
        unique: j['unique'] as bool? ?? false,
      );
}
