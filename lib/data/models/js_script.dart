class JsScript {
  final String id;
  final String name;
  final String description;
  final JsScriptSource source;
  final String content; // 脚本内容或路径
  final DateTime addedTime;
  final bool isBuiltIn;

  const JsScript({
    required this.id,
    required this.name,
    required this.description,
    required this.source,
    required this.content,
    required this.addedTime,
    this.isBuiltIn = false,
  });

  factory JsScript.fromMap(Map<String, dynamic> map) {
    return JsScript(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      source: JsScriptSource.values.firstWhere(
        (e) => e.name == (map['source'] as String),
        orElse: () => JsScriptSource.url,
      ),
      content: map['content'] as String,
      addedTime: DateTime.parse(map['addedTime'] as String),
      isBuiltIn: map['isBuiltIn'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'source': source.name,
      'content': content,
      'addedTime': addedTime.toIso8601String(),
      'isBuiltIn': isBuiltIn,
    };
  }

  JsScript copyWith({
    String? id,
    String? name,
    String? description,
    JsScriptSource? source,
    String? content,
    DateTime? addedTime,
    bool? isBuiltIn,
  }) {
    return JsScript(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      source: source ?? this.source,
      content: content ?? this.content,
      addedTime: addedTime ?? this.addedTime,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is JsScript && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

enum JsScriptSource {
  url('在线地址'),
  localFile('本地文件'),
  builtin('内置脚本');

  const JsScriptSource(this.displayName);
  final String displayName;
}