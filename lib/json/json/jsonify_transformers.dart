import 'package:kernel/ast.dart';
import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/type_environment.dart';
import 'package:transformer_template/src/phase/transformer_phase.dart';
import 'jsonify_const.dart';
import 'jsonify_from_json.dart';
import 'jsonify_to_json.dart';

@pragma('vm:entry-point')
class JsonifyTransformer extends TransformerPass {
  CoreTypes _coreTypes;
  ClassHierarchy _classHierarchy;
  StatefulStaticTypeContext _staticTypeContext;
  PrimaryFieldToJsonTrans primaryFieldTrans;
  JsonAbleFieldToJsonTrans jsonAbleFieldTrans;

  @override
  TreeNode visitComponent(Component node) {
    _coreTypes = CoreTypes(node);
    _classHierarchy = ClassHierarchy(node);
    _staticTypeContext = StatefulStaticTypeContext.stacked(
      TypeEnvironment(_coreTypes, _classHierarchy),
    );
    node.computeCanonicalNames();
    return super.visitComponent(node);
  }

  @override
  TreeNode visitLibrary(Library node) {
    _staticTypeContext.enterLibrary(node);
    final TreeNode result = super.visitLibrary(node);
    _staticTypeContext.leaveLibrary(node);
    return result;
  }

  @override
  TreeNode visitClass(Class node) {
    if (!checkIfClassIsAnnoWith(
      node.annotations,
      annotationName: K_JSONABLE_ID,
    )) {
      return super.visitClass(node);
    }

    /// Print Node.
    printNode(node);

    final List<Field> fields = node.fields;
    final Procedure toJson = node.procedures.firstWhere(
      (Procedure element) => element.name.name == 'toJson',
      orElse: () => null,
    );
    final Procedure fromJson = node.procedures.firstWhere(
      (Procedure element) => element.name.name == 'fromJson',
      orElse: () => null,
    );

    /// To Json Procedure.
    if (!EasyKernel.checkJsonModel(node, K_JSONMODEL_ID)) {
      return super.visitClass(node);
    }

    final Class target = node.enclosingComponent.libraries
        .map((lib) => lib.classes)
        .expand((i) => i)
        .firstWhere(
          (clazz) =>
              clazz.isAnonymousMixin &&
              clazz.name.contains(node.name) &&
              clazz.name.contains('JsonModel'),
        );

    final Procedure toJsonNewProce = generateToJson(fields, node);
    if (toJsonNewProce == null) {
      return super.visitClass(node);
    }
//    if (toJson == null) {
//      node.addMember(toJsonNewProce);
//    } else {
//      toJson.replaceChild(toJson.function, toJsonNewProce.function);
//    }
    if (target != null) {
//      target.replaceChild(target.procedures.firstWhere(((p) => p.name.name == 'toJson')),toJsonNewProce);
      Procedure toJson = target.procedures.firstWhere(((p) => p.name.name == 'toJson'));
      toJson.function = toJsonNewProce.function;
    }
    print('trans toJson method');
    print(toJsonNewProce);

    /// From Json Procedure.
    final Procedure fromJsonNewProce = generateFromJson(fields, node);
    if (fromJsonNewProce == null) {
      return super.visitClass(node);
    }
//    if (fromJson == null) {
//      node.addMember(fromJsonNewProce);
//    } else {
//      fromJson.replaceChild(fromJson.function, fromJsonNewProce.function);
//    }
    if (target != null) {
      Procedure fromJson = target.procedures.firstWhere(((p) => p.name.name == 'fromJson'));
      fromJson.function = fromJsonNewProce.function;
    }
    print('trans fromJson method');
    print(fromJsonNewProce);

    /// Print Node.
    printNode(node);

    return super.visitClass(node);
  }

//  @override
//  TreeNode visitMethodInvocation(MethodInvocation node) {
//    node.transformChildren(this);
//    final TreeNode Function() callSuper =
//        () => super.visitMethodInvocation(node);
//    if ((node.name.name == K_TO_JSON || node.name.name == K_FROM_JSON) &&
//        node.interfaceTargetReference != null) {
//      final Procedure procedure = node.interfaceTarget as Procedure;
//      if (procedure == null) {
//        return callSuper();
//      }
//      if (!checkIfClassIsAnnoWith(
//        procedure.annotations,
//        annotationName: K_JSONFUNCTION_ID,
//      )) {
//        return callSuper();
//      }
//
//      /// calculate
//      final InterfaceType type =
//          node.receiver.getStaticType(_staticTypeContext) as InterfaceType;
//      if (type == null) {
//        return callSuper();
//      }
//      final Class clazz = type.classNode;
//      final Procedure method = clazz.procedures.firstWhere(
//        (Procedure element) => element.name.name == node.name.name,
//        orElse: () => null,
//      );
//      node.replaceChild(node.interfaceTarget, method);
//      printNode(node);
//      return super.visitMethodInvocation(node);
//    }
//    return super.visitMethodInvocation(node);
//  }

  Procedure generateFromJson(List<Field> fields, Class node) {
    final VariableDeclaration declaration = VariableDeclaration(
      null,
      initializer: null,
      isRequired: true,
      type: EasyKernel.mapStringDynamicType(_coreTypes),
    );

    final JsonPropertyFieldFromJsonTrans trans = JsonPropertyFieldFromJsonTrans(
      _coreTypes,
      declaration,
    );
    final List<ExpressionStatement> namedExprList = fields
        .map((Field field) => field.accept(trans))
        .skipWhile((ExpressionStatement item) => item == null)
        .toList();

    final ReturnStatement returnStatement = ReturnStatement(ThisExpression());
    final Block block = Block(<Statement>[
      ...namedExprList,
      returnStatement,
    ]);

    final FunctionNode functionNode = FunctionNode(
      block,
      typeParameters: <TypeParameter>[],
      positionalParameters: <VariableDeclaration>[declaration],
      namedParameters: <VariableDeclaration>[],
      requiredParameterCount: 1,
      returnType: node.getThisType(_coreTypes, Nullability.legacy),
      asyncMarker: AsyncMarker.Sync,
      dartAsyncMarker: AsyncMarker.Sync,
    );

    final Procedure procedure = Procedure(
      Name(K_FROM_JSON, node.enclosingLibrary),
      ProcedureKind.Method,
      functionNode,
      isStatic: false,
      fileUri: node.fileUri,
      forwardingStubSuperTarget: null,
      forwardingStubInterfaceTarget: null,
    );

    procedure.fileOffset = node.fileOffset;
    procedure.fileEndOffset = node.fileEndOffset;
    procedure.startFileOffset = node.startFileOffset;
    procedure.addAnnotation(EasyKernel.entryPointerAnnotation(_coreTypes));
    printNode(node);
    return procedure;
  }

  Procedure generateToJson(List<Field> fields, Class node) {
    final DartType stringType = _coreTypes.stringLegacyRawType;
    const DartType dynamicType = DynamicType();
    final InterfaceType returnType = InterfaceType(
      _coreTypes.mapClass,
      Nullability.legacy,
      <DartType>[stringType, dynamicType],
    );

    final trans = JsonPropertyFieldToJsonTrans(_coreTypes);

    final List<MapEntry> entries = fields
        .map(
          (Field field) => field.accept(trans),
        )
        .skipWhile(
          (MapEntry entry) => entry.value == null || entry.key == null,
        )
        .toList(growable: true);

    final MapLiteral mapLiteral = MapLiteral(
      entries,
      keyType: stringType,
      valueType: dynamicType,
    );
    final ReturnStatement returnStatement = ReturnStatement(mapLiteral);
    final Block block = Block(<Statement>[
      returnStatement,
    ]);

    final FunctionNode functionNode = FunctionNode(
      block,
      typeParameters: <TypeParameter>[],
      positionalParameters: <VariableDeclaration>[],
      namedParameters: <VariableDeclaration>[],
      requiredParameterCount: 0,
      returnType: returnType,
      asyncMarker: AsyncMarker.Sync,
      dartAsyncMarker: AsyncMarker.Sync,
    );

    final Procedure procedure = Procedure(
      Name(K_TO_JSON, node.enclosingLibrary),
      ProcedureKind.Method,
      functionNode,
      isStatic: false,
      fileUri: node.fileUri,
      forwardingStubSuperTarget: null,
      forwardingStubInterfaceTarget: null,
    );

    procedure.fileOffset = node.fileOffset;
    procedure.fileEndOffset = node.fileEndOffset;
    procedure.startFileOffset = node.startFileOffset;
    procedure.addAnnotation(EasyKernel.entryPointerAnnotation(_coreTypes));
    return procedure;
  }

  DartType mapStringDynamicType() {
    final DartType stringType = _coreTypes.stringLegacyRawType;
    const DartType dynamicType = DynamicType();
    final InterfaceType returnType = InterfaceType(
      _coreTypes.mapClass,
      Nullability.legacy,
      <DartType>[stringType, dynamicType],
    );
    return returnType;
  }

  @override
  String name() => 'jsonify';
}
