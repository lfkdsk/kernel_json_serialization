import 'package:kernel/ast.dart';
import 'package:kernel/core_types.dart';
import 'package:transformer_template/src/phase/kernel_helper.dart';

import 'jsonify_const.dart';

/// Jsonify - ToJson Passes
/// @author liufengkai@bytedance.com
///

/// PrimaryField: int, double, string, bool
/// example: this.<name>
class PrimaryFieldToJsonTrans extends MemberVisitor<Expression> {
  @override
  Expression visitField(Field field) {
    return PropertyGet(
      ThisExpression(),
      Name(field.name.name),
    );
  }
}

/// JsonAbleField: @JsonAble and mix-on JsonAble class
/// example: this.<name>.toJson()
class JsonAbleFieldToJsonTrans extends MemberVisitor<Expression> {
  JsonAbleFieldToJsonTrans();

  @override
  Expression visitField(Field field) {
    /// value == null ? null : value.toJson();
    return MethodInvocation(
      PropertyGet(ThisExpression(), field.name),
      Name(K_TO_JSON),
      Arguments.empty(),
    );
  }
}

/// JsonIgnoreField: @JsonIgnore
/// example: null_literal.
class JsonIgnoreFieldTrans extends MemberVisitor<Expression> {
  @override
  Expression visitField(Field node) {
    if (checkIfClassIsAnnoWith(
      node.annotations,
      annotationName: K_JSONIGNORE_ID,
    )) {
      return NullLiteral();
    }
    return super.visitField(node);
  }
}

class JsonGenericFieldToJsonTrans extends MemberVisitor<Expression> {
  JsonGenericFieldToJsonTrans(this._propertyData);

  final JsonPropertyData _propertyData;

  @override
  Expression visitField(Field node) {
    final bool isGenericType = EasyKernel.isGenericType(node);
    if (!isGenericType) {
      return null;
    }
    final TypeParameterType typeParameterType = node.type;
    final TypeParameter parameter = typeParameterType.parameter;
    final Class justModel =
        EasyKernel.getSuperType(node.enclosingClass, K_JSONMODEL_ID);

    /// T extends JsonModel<T>
    if (parameter.bound ==
        InterfaceType(
          justModel,
          Nullability.legacy,
          <DartType>[typeParameterType],
        )) {
      final trans = JsonAbleFieldToJsonTrans();
      return node.accept(trans);
    }

    /// @JsonProperty(toJson: xxx)

    return super.visitField(node);
  }
}

/// JsonIterator Field : this.name
class JsonIteratorFieldToJsonTrans extends MemberVisitor<Expression> {
  JsonIteratorFieldToJsonTrans(this._types);

  final CoreTypes _types;

  @override
  Expression visitField(Field field) {
    return PropertyGet(
      ThisExpression(),
      Name(field.name.name),
    );
  }
}

/// JsonMap Field: this.<name>
class JsonMapFieldToJsonTrans extends MemberVisitor<Expression> {
  @override
  Expression visitField(Field field) {
    return PropertyGet(
      ThisExpression(),
      Name(field.name.name),
    );
  }
}

/// JsonProperty UserDefine
/// example: <static_method>.call(this.name)
class JsonPropertyUserDefineToJsonTrans extends MemberVisitor<Expression> {
  JsonPropertyUserDefineToJsonTrans(this.data, this._coreTypes);

  final JsonPropertyData data;
  final CoreTypes _coreTypes;

  @override
  Expression visitField(Field node) {
    data.toJson.procedure.addAnnotation(
      EasyKernel.entryPointerAnnotation(_coreTypes),
    );
    // TODO(liufengkai): nodes type check.
    return StaticInvocation(
      data.toJson.procedure,
      Arguments(<Expression>[
        PropertyGet(
          ThisExpression(),
          Name(node.name.name),
        )
      ]),
    );
  }
}

/// JsonCommonField: all property types.
/// example: this.<name> == null ? <null_literal> : (sub pass result).
class JsonCommonFieldToJsonTrans extends MemberVisitor<Expression> {
  JsonCommonFieldToJsonTrans(this._coreTypes, this._propertyData)
      : _primaryFieldTrans = PrimaryFieldToJsonTrans(),
        _jsonAbleFieldTrans = JsonAbleFieldToJsonTrans(),
        _userDefineToJsonTrans =
            JsonPropertyUserDefineToJsonTrans(_propertyData, _coreTypes),
        _genericFieldToJsonTrans = JsonGenericFieldToJsonTrans(_propertyData),
        _iteratorFieldToJsonTrans = JsonIteratorFieldToJsonTrans(_coreTypes),
        _mapFieldToJsonTrans = JsonMapFieldToJsonTrans();
  final CoreTypes _coreTypes;
  final JsonPropertyData _propertyData;
  final PrimaryFieldToJsonTrans _primaryFieldTrans;
  final JsonAbleFieldToJsonTrans _jsonAbleFieldTrans;
  final JsonPropertyUserDefineToJsonTrans _userDefineToJsonTrans;
  final JsonGenericFieldToJsonTrans _genericFieldToJsonTrans;
  final JsonIteratorFieldToJsonTrans _iteratorFieldToJsonTrans;
  final JsonMapFieldToJsonTrans _mapFieldToJsonTrans;

  /// user-def => function type.
  /// primary => node type.
  /// jsonable => Map<String, Dynamic>
  DartType getStaticType(
    bool isUserDefine,
    bool isPrimaryType,
    bool isJsonAble,
    JsonPropertyData data,
    Field node,
  ) {
    if (isUserDefine && data.toJson != null) {
      return data.toJson.procedure.function.returnType;
    }

    if (isPrimaryType) {
      return node.type;
    }

    if (isJsonAble) {
      return EasyKernel.mapStringDynamicType(_coreTypes);
    }

    return const DynamicType();
  }

  @override
  Expression visitField(Field node) {
    if (checkIfClassIsAnnoWith(node.annotations,
        annotationName: K_JSONIGNORE_ID)) {
      return null;
    }

    Expression result;
    final bool isUserDefined = _propertyData.toJson != null;
    final bool isPrimaryType = EasyKernel.isPrimaryType(_coreTypes, node);
    final bool isJsonAble = EasyKernel.isSupportWith(node, K_JSONABLE_ID);
    final bool isGenericType = EasyKernel.isGenericType(node);
    final bool isIterableType = EasyKernel.isIterable(node, _coreTypes);
    final bool isMapType = EasyKernel.isMapType(node, _coreTypes);

    /// user-def first => primary => jsonable => generic type.
    if (isUserDefined) {
      result = node.accept(_userDefineToJsonTrans);
    } else if (isPrimaryType) {
      result = node.accept(_primaryFieldTrans);
    } else if (isJsonAble) {
      result = node.accept(_jsonAbleFieldTrans);
    } else if (isGenericType) {
      result = node.accept(_genericFieldToJsonTrans);
    } else if (isIterableType) {
      result = node.accept(_iteratorFieldToJsonTrans);
    } else if (isMapType) {
      result = node.accept(_mapFieldToJsonTrans);
    }

    /// object will call .toJson as default.

    if (result == null) {
      throw StateError(
        'unsupport type : $isGenericType ${node.type}, name: ${node.name}.',
      );
    }

    final bool nullable = _propertyData.nullable;
    final Constant defaultValue = _propertyData.defaultValue;

    /// non-nullable value && defaultValue is null.
    if (!nullable && defaultValue is NullConstant) {
      return result;
    }

    /// let v = this.name;
    final InterfaceType type = node.type as InterfaceType;
    final VariableDeclaration declaration = VariableDeclaration(
      null,
      type: type,
      initializer: PropertyGet(ThisExpression(), node.name),
    );

    /// v == null ? default value : result.
    return EasyKernel.conditionIfNull(
      declaration,
      ConstantExpression(defaultValue, node.type),
      result,
      getStaticType(
        isUserDefined,
        isPrimaryType,
        isJsonAble,
        _propertyData,
        node,
      ),
    );
    // TODO(liufengkai): add other types here.
  }
}

/// JsonProperty Field: all types
/// example: => MapEntry(<name_pass_result>, <value_pass_result>);
class JsonPropertyFieldToJsonTrans extends MemberVisitor<MapEntry> {
  JsonPropertyFieldToJsonTrans(this._coreTypes);

  final CoreTypes _coreTypes;

  @override
  MapEntry visitField(Field node) {
    final Node annotation = getAnnotationByName(
      node.annotations,
      K_JSONPROPERTY_ID,
    );

    JsonPropertyData data;
    if (annotation == null) {
      data = JsonPropertyData.empty();
    } else {
      final getter = JsonPropertyCollectTrans(
        K_JSONPROPERTY_ID,
        K_JSON_PROPERTY_LIST,
      );
      data = node.accept(getter);
    }

    final JsonCommonFieldToJsonTrans trans =
        JsonCommonFieldToJsonTrans(_coreTypes, data);
    String name = node.name.name;

    /// User Define Property Name.
    if (data.name != null) {
      name = data.name;
    }

    /// CodeGen For Name
    final StringLiteral nameLiteral = StringLiteral(name);
    return MapEntry(nameLiteral, node.accept(trans));
  }
}
