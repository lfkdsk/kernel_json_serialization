import 'dart:core';
import 'package:kernel/ast.dart';
import 'package:kernel/core_types.dart';
import 'package:transformer_template/src/phase/kernel_helper.dart';
import 'jsonify_const.dart';

/// MethodInvocation: json_map['name']
MethodInvocation createJsonGet(
  VariableDeclaration declaration,
  Field field,
  String key,
) {
  final MethodInvocation invocation = MethodInvocation(
    VariableGet(declaration),
    Name('[]'),
    Arguments(
      <Expression>[
        StringLiteral(key),
      ],
    ),
  );
  return invocation;
}

class JsonPrimaryFieldFromJsonTrans extends MemberVisitor<Expression> {
  JsonPrimaryFieldFromJsonTrans(this.mapArg, this.name);

  final VariableDeclaration mapArg;
  final String name;

  @override
  Expression visitField(Field field) {
    /// json_map['name'] as Type
    final AsExpression asExpr = AsExpression(
      createJsonGet(mapArg, field, name),
      field.type,
    );
    return asExpr;
  }
}

class JsonAbleFieldFromJsonTrans extends MemberVisitor<Expression> {
  JsonAbleFieldFromJsonTrans(this.mapArg, this.name, this._types);

  final VariableDeclaration mapArg;
  final String name;
  final CoreTypes _types;

  @override
  Expression visitField(Field field) {
    final MethodInvocation invocation = createJsonGet(mapArg, field, name);
    final InterfaceType type = field.type as InterfaceType;
    final Class node = type.classNode;
    if (node.constructors == null || node.constructors.length != 1) {
//      throw StateError('JsonModel should has only one constructor.');
    }

    /// Model(<null>)
    final ConstructorInvocation constructorInvocation = ConstructorInvocation(
      node.constructors[0],
      Arguments.empty(),
    );

    /// json['name'] as Map<String, dynamic>
    final AsExpression asExpr = AsExpression(
      invocation,
      EasyKernel.mapStringDynamicType(_types),
    );

    /// Model().fromJson(json['name'] as Map<String, dynamic>)
    final MethodInvocation methodInvocation = MethodInvocation(
      constructorInvocation,
      Name(K_FROM_JSON),
      Arguments(<Expression>[asExpr]),
    );

    /// ... as Type.
    final AsExpression asExprPr = AsExpression(
      methodInvocation,
      node.getThisType(_types, Nullability.legacy),
    );
    return asExprPr;
  }
}

class JsonUserDefinedFieldFromJsonTrans extends MemberVisitor<Expression> {
  JsonUserDefinedFieldFromJsonTrans(this.data, this._coreTypes);

  final JsonPropertyData data;
  final CoreTypes _coreTypes;

  @override
  Expression visitField(Field node) {
    data.fromJson.procedure.addAnnotation(
      EasyKernel.entryPointerAnnotation(_coreTypes),
    );
    // TODO(liufengkai): nodes type check.
    /// this.fromJson(this.<name>)
    return StaticInvocation(
      data.fromJson.procedure,
      Arguments(<Expression>[
        PropertyGet(
          ThisExpression(),
          Name(node.name.name),
        )
      ]),
    );
  }
}

class JsonGenericFieldFromJsonTrans extends MemberVisitor<Expression> {
  JsonGenericFieldFromJsonTrans(this.mapArg, this.name, this._types);

  final VariableDeclaration mapArg;
  final String name;
  final CoreTypes _types;

  @override
  Expression visitField(Field node) {
    final bool isGenericType = EasyKernel.isGenericType(node);
    if (!isGenericType) {
      return null;
    }
    final TypeParameterType typeParameterType = node.type;
    final TypeParameter parameter = typeParameterType.parameter;
    final Class justModel = EasyKernel.getSuperType(
      node.enclosingClass,
      K_JSONMODEL_ID,
    );

    /// T extends JsonModel<T>
    if (parameter.bound ==
        InterfaceType(
          justModel,
          Nullability.legacy,
          <DartType>[typeParameterType],
        )) {
      final trans = JsonAbleFieldFromJsonTrans(mapArg, name, _types);
      return node.accept(trans);
    }

    return super.visitField(node);
  }
}

class JsonIterableFieldFromJsonTrans extends MemberVisitor<Expression> {
  JsonIterableFieldFromJsonTrans(this.mapArg, this.name, this._types);

  final VariableDeclaration mapArg;
  final String name;
  final CoreTypes _types;

  static FunctionExpression generateInner(
      CoreTypes _types, Field field, InterfaceType itemType,
      {String name}) {
    final VariableDeclaration del = VariableDeclaration(
      name,
      type: const DynamicType(),
    );
    return FunctionExpression(
      FunctionNode(
        ReturnStatement(
          generateExpr(_types, field, itemType, del),
        ),
        positionalParameters: [del],
        returnType: itemType,
      ),
    );
  }

  static Expression generateExpr(
    CoreTypes _types,
    Field field,
    InterfaceType itemType,
    VariableDeclaration del,
  ) {
    if (EasyKernel.isPrimaryTypeWithType(_types, itemType)) {
      return AsExpression(VariableGet(del), itemType);
    }

    if (EasyKernel.isGenericTypeWithType(itemType)) {
      throw StateError(
        'field ${field.name.toString()} is generic type in fromJson, but not spec `fromJson` method.',
      );
    }

    if (EasyKernel.isSupportWithType(itemType, K_JSONABLE_ID)) {
      final InterfaceType type = itemType;
      final Class node = type.classNode;
      if (node.constructors == null || node.constructors.length != 1) {
//        throw StateError('JsonModel should has only one constructor.');
      }
      if (node.constructors.isEmpty) {
        throw (node.constructors);
      }

      /// Model(<null>)
      final ConstructorInvocation constructorInvocation = ConstructorInvocation(
        node.constructors[0],
        Arguments.empty(),
      );

      /// e as Map<String, dynamic>
      final AsExpression asExpr = AsExpression(
        VariableGet(del),
        EasyKernel.mapStringDynamicType(_types),
      );

      /// Model().fromJson(e as Map<String, dynamic>)
      final MethodInvocation methodInvocation = MethodInvocation(
        constructorInvocation,
        Name(K_FROM_JSON),
        Arguments(<Expression>[asExpr]),
      );

      /// e == null ? null : Model().fromJson(e as Map<String, dynamic>)
      final nullCon = ConditionalExpression(
        MethodInvocation(
          VariableGet(del),
          Name('=='),
          Arguments(<Expression>[NullLiteral()]),
        ),
        NullLiteral(),
        methodInvocation,
        itemType,

        /// Inner Type.
      );

      return nullCon;
    }

    if (EasyKernel.isIterableWithType(itemType, _types)) {
      final InterfaceType innerType = itemType.typeArguments[0];

      /// (e as List)
      final callAs = AsExpression(VariableGet(del), _types.listLegacyRawType);
      final callAsVar = VariableDeclaration(null, initializer: callAs);

      /// (e as List).?map( => )
      final asToMap = Let(
        callAsVar,
        ConditionalExpression(
          MethodInvocation(
            VariableGet(callAsVar),
            Name('=='),
            Arguments(<Expression>[NullLiteral()]),
          ),
          NullLiteral(),
          MethodInvocation(
            VariableGet(callAsVar),
            Name('map'),
            Arguments(<Expression>[
              generateInner(
                _types,
                field,
                innerType,
              ),

              /// Inner Type.
            ], types: [
              innerType,
            ]),
          ),
          EasyKernel.iterableIt(_types, innerType),

          /// Inner Type.
        ),
      );
      final asToMapVar = VariableDeclaration(null, initializer: asToMap);

      /// (e as List).?map( => ).?toList()
      final asToList = Let(
        asToMapVar,
        ConditionalExpression(
          MethodInvocation(
            VariableGet(asToMapVar),
            Name('=='),
            Arguments(<Expression>[NullLiteral()]),
          ),
          NullLiteral(),
          MethodInvocation(
            VariableGet(asToMapVar),
            Name('toList'),
            Arguments.empty(),
          ),
          itemType,

          /// Upper Type.
        ),
      );

      /// (e) => (e as List).?
      return asToList;
    }

    if (EasyKernel.isMapWithType(itemType, _types)) {
      final InterfaceType genericListType = itemType;
      final InterfaceType stringType = genericListType.typeArguments[0];
      final InterfaceType innerType = genericListType.typeArguments[1];

      /// (k, v) => MapEntry()
      final callIter = JsonMapFieldFromJsonTrans.generateInner(
        _types,
        field,
        innerType,
      );

      /// (e as Map<String, dynamic>)
      final asExpr = AsExpression(
        VariableGet(del),
        EasyKernel.mapStringDynamicType(_types),
      );

      /// (e as Map<String, dynamic>)?.map( callIterator );
      final nullCon = ConditionalExpression(
        MethodInvocation(
          asExpr,
          Name('=='),
          Arguments(<Expression>[NullLiteral()]),
        ),
        NullLiteral(),
        MethodInvocation(
          asExpr,
          Name('map'),
          Arguments(<Expression>[callIter], types: [stringType, innerType]),
        ),
        itemType,
      );

      return nullCon;
    }

    return null;
  }

  @override
  Expression visitField(Field field) {
    if (field.type is! InterfaceType ||
        (field.type as InterfaceType).typeArguments.length > 1) {
      return super.visitField(field);
    }
    final InterfaceType genericListType = field.type;
    final InterfaceType itemType = genericListType.typeArguments[0];

    /// json[name]
    final MethodInvocation invocation = createJsonGet(mapArg, field, name);

    /// json['name'] as List
    final AsExpression asExpr = AsExpression(
      invocation,
      _types.listLegacyRawType,
    );

    /// (json['name'] as List)
    final asValue = VariableDeclaration(null, initializer: asExpr);

    /// (json['name'] as List)?.map((e) => e as <primary type>)
    final asToMap = Let(
      asValue,
      ConditionalExpression(
        MethodInvocation(
          VariableGet(asValue),
          Name('=='),
          Arguments(<Expression>[NullLiteral()]),
        ),
        NullLiteral(),
        MethodInvocation(
          VariableGet(asValue),
          Name('map'),
          Arguments(<Expression>[
            generateInner(_types, field, itemType),
          ], types: [
            itemType
          ]),
        ),
        EasyKernel.iterableIt(_types, itemType),
      ),
    );
    final asToListVar = VariableDeclaration(null, initializer: asToMap);

    /// (json['name'] as List)?.map((e) => e as <primary type>)?.toList()
    final asToList = Let(
      asToListVar,
      ConditionalExpression(
        MethodInvocation(
          VariableGet(asToListVar),
          Name('=='),
          Arguments(<Expression>[NullLiteral()]),
        ),
        NullLiteral(),
        MethodInvocation(
          VariableGet(asToListVar),
          Name('toList'),
          Arguments.empty(),
        ),
        genericListType,
      ),
    );
    return asToList;
  }
}

class JsonMapFieldFromJsonTrans extends MemberVisitor<Expression> {
  JsonMapFieldFromJsonTrans(this.mapArg, this.name, this._types);

  final VariableDeclaration mapArg;
  final String name;
  final CoreTypes _types;

  @override
  Expression visitField(Field field) {
    if (field.type is! InterfaceType ||
        (field.type as InterfaceType).typeArguments.length != 2) {
      return super.visitField(field);
    }
    final InterfaceType genericListType = field.type;
    final InterfaceType stringType = genericListType.typeArguments[0];
    final InterfaceType itemType = genericListType.typeArguments[1];

    /// json[name]
    final MethodInvocation invocation = createJsonGet(mapArg, field, name);

    /// json['name'] as Map<String, dynamic>
    final AsExpression asExpr = AsExpression(
      invocation,
      EasyKernel.mapStringDynamicType(_types),
    );

    /// (json['name'] as Map<String, dynamic>)
    final asValue = VariableDeclaration(null,
        initializer: asExpr, type: EasyKernel.mapStringDynamicType(_types));

    /// (json['name'] as Map<String, dynamic>)?.map((e) => MapEntry())
    final asToMap = Let(
      asValue,
      ConditionalExpression(
        MethodInvocation(
          VariableGet(asValue),
          Name('=='),
          Arguments(<Expression>[NullLiteral()]),
        ),
        NullLiteral(),
        MethodInvocation(
          VariableGet(asValue),
          Name('map'),
          Arguments(<Expression>[
            generateInner(_types, field, itemType),
          ], types: [
            _types.stringLegacyRawType,
            itemType
          ]),
        ),
        EasyKernel.mapStringIt(_types, itemType),
      ),
    );
    return asToMap;
  }

  static FunctionExpression generateInner(
    CoreTypes _types,
    Field field,
    InterfaceType itemType,
  ) {
    final VariableDeclaration key = VariableDeclaration(
      'k',
      type: _types.stringLegacyRawType,
    );
    final VariableDeclaration value = VariableDeclaration(
      'e',
      type: const DynamicType(),
    );

    return FunctionExpression(
      FunctionNode(
        ReturnStatement(generateExpr(_types, field, itemType, key, value)),
        positionalParameters: [key, value],
        returnType: EasyKernel.mapEntryStringIt(_types, itemType),
        requiredParameterCount: 2,
      ),
    );
  }

  static Expression generateExpr(
    CoreTypes _types,
    Field field,
    InterfaceType itemType,
    VariableDeclaration key,
    VariableDeclaration value,
  ) {
    final constructor = _types.index.tryGetMember('dart:core', 'MapEntry', '_');
    if (constructor == null) {
      throw 'Cannot fetch dart.core::MapEntry';
    }

    if (EasyKernel.isPrimaryTypeWithType(_types, itemType)) {
      return ConstructorInvocation(
        constructor,
        Arguments([
          VariableGet(key),
          ConditionalExpression(
            MethodInvocation(
              VariableGet(value),
              Name('=='),
              Arguments([NullLiteral()]),
            ),
            NullLiteral(),
            AsExpression(VariableGet(value), itemType),
            itemType,
          )
        ], types: [
          _types.stringLegacyRawType,
          itemType
        ]),
      );
    }

    if (EasyKernel.isGenericTypeWithType(itemType)) {
      throw StateError(
        'field ${field.name.toString()} is generic type in fromJson, but not spec `fromJson` method.',
      );
    }

    if (EasyKernel.isSupportWithType(itemType, K_JSONABLE_ID)) {
      final InterfaceType type = itemType;
      final Class node = type.classNode;
      if (node.constructors == null || node.constructors.length != 1) {
//        throw StateError('JsonModel should has only one constructor.');
      }

      /// Model(<null>)
      final ConstructorInvocation constructorInvocation = ConstructorInvocation(
        node.constructors[0],
        Arguments.empty(),
      );

      /// e as Map<String, dynamic>
      final AsExpression asExpr = AsExpression(
        VariableGet(value),
        EasyKernel.mapStringDynamicType(_types),
      );

      /// Model().fromJson(e as Map<String, dynamic>)
      final MethodInvocation methodInvocation = MethodInvocation(
        constructorInvocation,
        Name(K_FROM_JSON),
        Arguments(<Expression>[asExpr]),
      );

      return ConstructorInvocation(
        constructor,
        Arguments([
          VariableGet(key),
          ConditionalExpression(
            MethodInvocation(
              VariableGet(value),
              Name('=='),
              Arguments([NullLiteral()]),
            ),
            NullLiteral(),
            methodInvocation,
            itemType,
          )
        ], types: [
          _types.stringLegacyRawType,
          itemType
        ]),
      );
    }

    if (EasyKernel.isIterableWithType(itemType, _types)) {
      final callIter = JsonIterableFieldFromJsonTrans.generateExpr(
        _types,
        field,
        itemType,
        value,
      );

      /// MapEntry(k, ((e as List) => xxxx)
      final conCall = ConstructorInvocation(
        constructor,
        Arguments(
          [
            VariableGet(key),
            callIter,
          ],
          types: [_types.stringLegacyRawType, itemType],
        ),
      );
      return conCall;
    }

    if (EasyKernel.isMapWithType(itemType, _types)) {
      final InterfaceType genericListType = itemType;
      final InterfaceType stringType = genericListType.typeArguments[0];
      final InterfaceType innerType = genericListType.typeArguments[1];

      /// (e as Map)
      final asExpr = AsExpression(
        VariableGet(value),
        EasyKernel.mapStringDynamicType(_types),
      );

      /// (e as Map)
      final asValue = VariableDeclaration(
        null,
        initializer: asExpr,
      );

      ///(e as Map)?.map((k, e) => MapEntry())
      final asToMap = Let(
        asValue,
        ConditionalExpression(
          MethodInvocation(
            VariableGet(asValue),
            Name('=='),
            Arguments(<Expression>[NullLiteral()]),
          ),
          NullLiteral(),
          MethodInvocation(
            VariableGet(asValue),
            Name('map'),
            Arguments(<Expression>[
              generateInner(_types, field, innerType),
            ], types: [
              _types.stringLegacyRawType,
              innerType
            ]),
          ),
          EasyKernel.mapStringIt(_types, innerType),
        ),
      );

      return ConstructorInvocation(
        constructor,
        Arguments([
          VariableGet(key),
          asToMap,
        ], types: [
          _types.stringLegacyRawType,
          itemType
        ]),
      );
    }
    return null;
  }
}

class JsonCommonFieldFromJsonTrans extends MemberVisitor<ExpressionStatement> {
  JsonCommonFieldFromJsonTrans(this._data, this._types, this.declaration);

  final JsonPropertyData _data;
  final CoreTypes _types;
  final VariableDeclaration declaration;

  @override
  ExpressionStatement visitField(Field node) {
    /// Map<String, dynamic> json

    Expression result;
    final bool isUserDefined = _data.fromJson != null;
    final bool isPrimaryType = EasyKernel.isPrimaryType(_types, node);
    final bool isJsonAble = EasyKernel.isSupportWith(node, K_JSONABLE_ID);
    final bool isGenericType = EasyKernel.isGenericType(node);
    final bool isIterableType = EasyKernel.isIterable(node, _types);
    final bool isMapType = EasyKernel.isMapType(node, _types);

    /// field name.
    String fieldName = node.name.name;
    if (_data.name != null) {
      fieldName = _data.name;
    }

    print('$node , $isGenericType $isIterableType $isJsonAble $isMapType');

    /// user-def first => primary => jsonable => generic type.
    if (isUserDefined) {
      result = node.accept(
        JsonUserDefinedFieldFromJsonTrans(_data, _types),
      );
    } else if (isPrimaryType) {
      result = node.accept(
        JsonPrimaryFieldFromJsonTrans(declaration, fieldName),
      );
    } else if (isJsonAble) {
      result = node.accept(
        JsonAbleFieldFromJsonTrans(declaration, fieldName, _types),
      );
    } else if (isGenericType) {
      throw StateError(
        'field $fieldName is generic type in fromJson, but not spec `fromJson` method.',
      );
    } else if (isIterableType) {
      result = node.accept(
        JsonIterableFieldFromJsonTrans(declaration, fieldName, _types),
      );
    } else if (isMapType) {
      result = node.accept(
        JsonMapFieldFromJsonTrans(declaration, fieldName, _types),
      );
    }

    if (result == null) {
      return null;
    }

    /// this.<name> = result.
    final assign = ExpressionStatement(
      PropertySet(
        ThisExpression(),
        node.name,
        result,
      ),
    );

    return assign;
  }
}

class JsonPropertyFieldFromJsonTrans
    extends MemberVisitor<ExpressionStatement> {
  JsonPropertyFieldFromJsonTrans(
    this._coreTypes,
    this.declaration,
  );

  final CoreTypes _coreTypes;
  final VariableDeclaration declaration;

  @override
  ExpressionStatement visitField(Field node) {
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

    final trans = JsonCommonFieldFromJsonTrans(data, _coreTypes, declaration);
    return node.accept(trans);
  }
}
