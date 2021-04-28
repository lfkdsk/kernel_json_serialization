import 'package:kernel/ast.dart';
import 'package:transformer_template/src/phase/kernel_helper.dart';


const String K_JSONABLE_ID = 'JsonAble';
const String K_JSONFUNCTION_ID = 'JsonFunction';
const String K_JSONMODEL_ID = 'JsonModel';
const String K_JSONPROPERTY_ID = 'JsonProperty';
const String K_JSONIGNORE_ID = 'JsonIgnore';
const String K_TO_JSON = 'toJson';
const String K_FROM_JSON = 'fromJson';
const String K_NAME = 'name';
const String K_NULLABLE = 'nullable';
const String K_INCLUDE_IF_NULL = 'includeIfNull';
const String K_DEFAULT_VALUE = 'defaultValue';
const String K_REQUIRED = 'required';
const String K_CONSTRUCTORS = 'constructors';
const List<String> K_JSON_PROPERTY_LIST = <String>[
  K_NAME,
  K_TO_JSON,
  K_FROM_JSON,
  K_NULLABLE,
  K_INCLUDE_IF_NULL,
  K_DEFAULT_VALUE,
  K_REQUIRED,
];

class JsonPropertyData {
  JsonPropertyData({
    this.name,
    this.toJson,
    this.fromJson,
    this.required,
    this.nullable,
    this.includeIfNull,
    this.defaultValue,
    this.constructors,
  });

  factory JsonPropertyData.empty() {
    return JsonPropertyData(
      name: null,
      toJson: null,
      fromJson: null,
      required: false,
      nullable: false,
      includeIfNull: false,
      defaultValue: NullConstant(),
      constructors: [],
    );
  }

  final String name;
  final TearOffConstant toJson;
  final TearOffConstant fromJson;
  final List<TearOffConstant> constructors;
  final bool required;
  final bool nullable;
  final bool includeIfNull;
  final Constant defaultValue;
}

/// JsonProperty Collect Pass
/// @JsonProperty(params) => result
class JsonPropertyCollectTrans extends MemberVisitor<JsonPropertyData> {
  JsonPropertyCollectTrans(String name, List<String> keys)
      : getter = AnnotationValueGetter(name, keys);

  final Map<Field, JsonPropertyData> collectProperties = {};
  final AnnotationValueGetter getter;

  @override
  JsonPropertyData visitField(Field node) {
    final Node annotation = getAnnotationByName(
      node.annotations,
      K_JSONPROPERTY_ID,
    );
    annotation.accept(getter);
    print(getter.result);
    return getJsonPropertyData();
  }

  JsonPropertyData getJsonPropertyData() {
    final Node nameNode = getter[K_NAME];
    final Node fromJsonNode = getter[K_FROM_JSON];
    final Node toJsonNode = getter[K_TO_JSON];
    final Node nullable = getter[K_NULLABLE];
    final Node includeIfNull = getter[K_INCLUDE_IF_NULL];
    final Node required = getter[K_REQUIRED];
    final Node defaultValue = getter[K_DEFAULT_VALUE];
    final Node constructors = getter[K_CONSTRUCTORS];
    return JsonPropertyData(
      name: (nameNode is NullConstant)
          ? null
          : (nameNode as StringConstant).value,
      fromJson: (fromJsonNode is NullConstant)
          ? null
          : (fromJsonNode as TearOffConstant),
      toJson:
          (toJsonNode is NullConstant) ? null : (toJsonNode as TearOffConstant),
      // bool values
      nullable: (nullable is! NullConstant) && (nullable as BoolConstant).value,
      required: (required is! NullConstant) && (required as BoolConstant).value,
      includeIfNull: (includeIfNull is! NullConstant) &&
          (includeIfNull as BoolConstant).value,
      // default value
      defaultValue: defaultValue as Constant,
      constructors: (constructors is NullConstant) ? null : constructors as List<TearOffConstant>,
    );
  }
}
