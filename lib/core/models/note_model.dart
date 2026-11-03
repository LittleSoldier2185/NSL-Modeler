class NoteModel {
  NoteModel({
    required this.id,
    required this.text,
    this.x = 0,
    this.y = 0,
    this.width = 190,
  });

  String id;
  String text;
  double x;
  double y;
  double width;

  Map<String, dynamic> toJson() =>
      {'id': id, 'text': text, 'x': x, 'y': y, 'width': width};

  factory NoteModel.fromJson(Map<String, dynamic> j) => NoteModel(
        id: j['id'] as String,
        text: j['text'] as String? ?? '',
        x: (j['x'] as num? ?? 0).toDouble(),
        y: (j['y'] as num? ?? 0).toDouble(),
        width: (j['width'] as num? ?? 190).toDouble(),
      );
}
