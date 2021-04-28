library just_jsonify_annotation;

@pragma('vm:entry-point')
class JsonAble {
  const factory JsonAble() = JsonAble._;

  @pragma('vm:entry-point')
  const JsonAble._();
}

@pragma('vm:entry-point')
class JsonFunction {
  const factory JsonFunction() = JsonFunction._;

  @pragma('vm:entry-point')
  const JsonFunction._();
}

enum Type { CALL, INJECT, RUN }

@pragma('vm:entry-point')
class JsonProperty {
  @pragma('vm:entry-point')
  const JsonProperty({
    this.name,
    this.toJson,
    this.fromJson,
    this.required,
    this.nullable,
    this.includeIfNull,
    this.defaultValue,
    this.constructors,
  });

  final String name;
  final Function toJson;
  final Function fromJson;
  final List<Function> constructors;
  final bool required;
  final bool nullable;
  final bool includeIfNull; // TODO(liufengkai): could not support now, includeIfNull is always true.
  final Object defaultValue;
}

@pragma('vm:entry-point')
class JsonIgnore {
  const factory JsonIgnore() = JsonIgnore._;

  @pragma('vm:entry-point')
  const JsonIgnore._();
}

@pragma('vm:entry-point')
mixin JsonModel<T> {
  @pragma('vm:entry-point')
  @JsonFunction()
  Map<String, dynamic> toJson() {
    return <String, dynamic>{}.map((k, e) => MapEntry(k, e));
  }

  @pragma('vm:entry-point')
  @JsonFunction()
  T fromJson(Map<String, dynamic> json) {
    return this as T;
  }
}

Map<String, dynamic> toJson(dynamic object) {
  return object.toJson();
}

T fromJson<T>(
  JsonModel<T> Function() constructor,
  Map<String, dynamic> json,
) {
  return constructor().fromJson(json);
}
