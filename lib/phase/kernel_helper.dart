import 'dart:io';
import 'package:kernel/ast.dart';
import 'package:kernel/binary/ast_to_binary.dart';
import 'package:kernel/binary/ast_from_binary.dart';
import 'package:kernel/binary/limited_ast_to_binary.dart';
import 'package:kernel/core_types.dart';

import 'package:kernel/kernel.dart' show Component;
import 'package:kernel/kernel.dart' hide MapEntry;
import 'package:kernel/binary/ast_from_binary.dart'
    show BinaryBuilderWithMetadata;
import 'package:kernel/text/ast_to_text.dart';
import 'package:transformer_template/src/phase/transformer_phase.dart';
import 'logging.dart' as logging;

final logging.Logger logger = logging.Logger('Trans');

bool isDebug = false;

dynamic deepCopyASTNode(
  dynamic node, {
  bool isReturnType = false,
  bool ignoreGenerics = false,
}) {
  if (node is TypeParameter) {
    if (ignoreGenerics) {
      return TypeParameter(node.name, node.bound, node.defaultType);
    }
  }
  if (node is VariableDeclaration) {
    return VariableDeclaration(
      node.name,
      initializer: node.initializer,
      type: deepCopyASTNode(node.type) as DartType,
      flags: node.flags,
      isFinal: node.isFinal,
      isConst: node.isConst,
      isFieldFormal: node.isFieldFormal,
      isCovariant: node.isCovariant,
    );
  }
  if (node is TypeParameterType) {
    if (isReturnType || ignoreGenerics) {
      return const DynamicType();
    }
    return TypeParameterType(
      deepCopyASTNode(node.parameter) as TypeParameter,
      deepCopyASTNode(node.nullability) as Nullability,
      deepCopyASTNode(node.promotedBound) as DartType,
    );
  }
  if (node is FunctionType) {
    return FunctionType(
      deepCopyASTNodes(node.positionalParameters),
      deepCopyASTNode(node.returnType, isReturnType: true) as DartType,
      Nullability.legacy,
      namedParameters: deepCopyASTNodes(node.namedParameters),
      typeParameters: deepCopyASTNodes(node.typeParameters),
      requiredParameterCount: node.requiredParameterCount,
      typedefType: deepCopyASTNode(
        node.typedefType,
        ignoreGenerics: ignoreGenerics,
      ) as TypedefType,
    );
  }
  if (node is TypedefType) {
    return TypedefType(
      node.typedefNode,
      Nullability.legacy,
      deepCopyASTNodes(node.typeArguments, ignoreGeneric: ignoreGenerics),
    );
  }
  if (node is InterfaceType) {
    return InterfaceType(
      node.classNode,
      node.nullability,
      deepCopyASTNodes(
        node.typeArguments,
        ignoreGeneric: ignoreGenerics,
      ),
    );
  }
  return node;
}

List<T> deepCopyASTNodes<T>(List<T> nodes, {bool ignoreGeneric = false}) {
  final List<T> newNodes = <T>[];
  for (T node in nodes) {
    final dynamic newNode = deepCopyASTNode(
      node,
      ignoreGenerics: ignoreGeneric,
    );
    if (newNode != null) {
      newNodes.add(newNode as T);
    }
  }
  return newNodes;
}

Node printNode(Node node, {TransformerPass pass}) {
  if (!isDebug) {
    return node;
  }

  final StringBuffer newBuffer = StringBuffer();
  Printer(newBuffer, showOffsets: true, showMetadata: true).writeNode(node);
  logger.info(
    '${pass != null ? 'Pass: ' : ''}${pass != null ? pass.name() : ''} print ${node.toString()} start',
  );
  print(newBuffer);
  logger.info(
    '${pass != null ? 'Pass: ' : ''}${pass != null ? pass.name() : ''} print ${node.toString()} end',
  );

  return node;
}

String nodeToString(Node node) {
  final StringBuffer newBuffer = StringBuffer();
  Printer(newBuffer, showOffsets: true, showMetadata: true).writeNode(node);
  return newBuffer.toString();
}

bool checkIfClassIsAnnoWith(
  List<Expression> annotations, {
  String annotationName,
}) {
  return getAnnotationByName(annotations, annotationName) != null;
}

Node getAnnotationByName(List<Expression> annotations, String annotationName) {
  for (final Expression annotation in annotations) {
    /// Release Mode
    if (annotation is ConstantExpression) {
      final ConstantExpression constantExpression = annotation;
      final Constant constant = constantExpression.constant;
      if (constant is InstanceConstant) {
        final InstanceConstant instanceConstant = constant;
        final CanonicalName canonicalName =
            instanceConstant.classReference.canonicalName;
        if (canonicalName.name == annotationName) {
          return constantExpression;
        }
      }
    }

    /// Debug Mode
    else if (annotation is ConstructorInvocation) {
      final ConstructorInvocation constructorInvocation = annotation;
      final Class cls =
          constructorInvocation.targetReference.node?.parent as Class;
      if (cls == null) {
        continue;
      }
      final Library library = cls?.parent as Library;
      if (cls.name == annotationName) {
        return constructorInvocation;
      }
    }
  }

  return null;
}

class EasyKernel {
  static bool isPrimaryType(CoreTypes _coreTypes, Field field) {
    return field.type == _coreTypes.intLegacyRawType ||
        field.type == _coreTypes.doubleLegacyRawType ||
        field.type == _coreTypes.stringLegacyRawType ||
        field.type == _coreTypes.boolLegacyRawType;
  }

  static bool isPrimaryTypeWithType(CoreTypes _coreTypes, DartType type) {
    return type == _coreTypes.intLegacyRawType ||
        type == _coreTypes.doubleLegacyRawType ||
        type == _coreTypes.stringLegacyRawType ||
        type == _coreTypes.boolLegacyRawType;
  }

  static DartType mapStringDynamicType(CoreTypes _coreTypes) {
    final DartType stringType = _coreTypes.stringLegacyRawType;
    const DartType dynamicType = DynamicType();
    final InterfaceType returnType = InterfaceType(
      _coreTypes.mapClass,
      Nullability.legacy,
      <DartType>[stringType, dynamicType],
    );
    return returnType;
  }

  static bool isSupportWith(Field field, String annoName) {
    if (field.type is! InterfaceType) {
      return false;
    }

    final InterfaceType type = field.type as InterfaceType;
    final Class node = type.classNode;
    return checkIfClassIsAnnoWith(
      node.annotations,
      annotationName: annoName,
    );
  }

  static bool isSupportWithType(DartType fieldType, String annoName) {
    if (fieldType is! InterfaceType) {
      return false;
    }

    final InterfaceType type = fieldType as InterfaceType;
    final Class node = type.classNode;
    return checkIfClassIsAnnoWith(
      node.annotations,
      annotationName: annoName,
    );
  }

  static bool isGenericType(Field field) {
    return field.type is TypeParameterType;
  }

  static bool isGenericTypeWithType(DartType type) => type is TypeParameterType;

  static Class getSuperType(Class clazz, String name) {
    final Class superClazz = clazz.supertype.classNode;
    while (superClazz != null) {
      if (superClazz.implementedTypes == null) {
        continue;
      }
      for (final Supertype value in superClazz.implementedTypes) {
        if (value.classNode.name == name) {
          return value.classNode;
        }
      }
    }

    return null;
  }

  static bool checkJsonModel(Class clazz, String name) {
    final Class superClazz = clazz.supertype.classNode;
    while (superClazz != null) {
      if (superClazz.implementedTypes == null) {
        continue;
      }
      for (final Supertype value in superClazz.implementedTypes) {
        if (value.classNode.name == name) {
          return true;
        }
      }
    }
    return false;
  }

  static ConstantExpression entryPointerAnnotation(CoreTypes _coreTypes) {
    return ConstantExpression(
      InstanceConstant(
        _coreTypes.pragmaClass.reference,
        [],
        {
          _coreTypes.pragmaName.reference: StringConstant('vm:entry-point'),
          _coreTypes.pragmaOptions.reference: NullConstant(),
        },
      ),
    );
  }

  static bool isIterator(Field field, CoreTypes coreTypes) {
    if (field.type is! InterfaceType) {
      return false;
    }

    final InterfaceType type = field.type as InterfaceType;
    final Class node = type.classNode;
    return node == coreTypes.iterableClass;
  }

  static bool isIteratorWithType(DartType fieldType, CoreTypes coreTypes) {
    if (fieldType is! InterfaceType) {
      return false;
    }

    final InterfaceType type = fieldType as InterfaceType;
    final Class node = type.classNode;
    return node == coreTypes.iterableClass;
  }

  static bool isList(Field field, CoreTypes coreTypes) {
    if (field.type is! InterfaceType) {
      return false;
    }

    final InterfaceType type = field.type as InterfaceType;
    final Class node = type.classNode;
    return node == coreTypes.listClass;
  }

  static bool isListWithType(DartType fieldType, CoreTypes coreTypes) {
    if (fieldType is! InterfaceType) {
      return false;
    }

    final InterfaceType type = fieldType as InterfaceType;
    final Class node = type.classNode;
    return node == coreTypes.listClass;
  }

  static bool isIterable(Field field, CoreTypes coreTypes) {
    return isIterator(field, coreTypes) || isList(field, coreTypes);
  }

  static bool isIterableWithType(DartType field, CoreTypes coreTypes) {
    return isIteratorWithType(field, coreTypes) ||
        isListWithType(field, coreTypes);
  }

  static bool isMapType(Field field, CoreTypes coreTypes) {
    if (field.type is! InterfaceType) {
      return false;
    }

    final InterfaceType type = field.type as InterfaceType;
    final Class node = type.classNode;
    return node == coreTypes.mapClass;
  }

  static bool isMapWithType(DartType fieldType, CoreTypes coreTypes) {
    if (fieldType is! InterfaceType) {
      return false;
    }

    final InterfaceType type = fieldType as InterfaceType;
    final Class node = type.classNode;
    return node == coreTypes.mapClass;
  }

  static Expression conditionIfNull(
    VariableDeclaration declaration,
    Expression defaultValue,
    Expression elseIf,
    DartType staticType,
  ) {
    return Let(
      declaration,
      ConditionalExpression(
        MethodInvocation(
          VariableGet(declaration),
          Name('=='),
          Arguments(<Expression>[NullLiteral()]),
        ),
        defaultValue,
        elseIf,
        staticType,
      ),
    );
  }

  static DartType iterableIt(CoreTypes _types, DartType innerType) {
    return InterfaceType(
      _types.iterableClass,
      Nullability.legacy,
      <DartType>[innerType],
    );
  }

  static DartType mapStringIt(CoreTypes _types, DartType innerType) {
    return InterfaceType(
      _types.mapClass,
      Nullability.legacy,
      <DartType>[_types.stringLegacyRawType, innerType],
    );
  }

  static DartType listIt(CoreTypes _types, DartType innerType) {
    return InterfaceType(
      _types.listClass,
      Nullability.legacy,
      <DartType>[innerType],
    );
  }

  static DartType mapEntryStringIt(CoreTypes _types, DartType innerType) {
    return InterfaceType(
      _types.index.tryGetClass('dart:core', 'MapEntry'),
      Nullability.legacy,
      <DartType>[_types.stringLegacyRawType, innerType],
    );
  }

  static List<dynamic> getObjFromInstantConst(InstanceConstant instance) {
    final result = [];
    for (var value in instance.fieldValues.values) {
      if (value is IntConstant) {
        result.add(value.value);
      } else if (value is StringConstant) {
        result.add(value.value);
      }
    }
    return result;
  }

  static Map<String, dynamic> getMapFromInstantConst(
    InstanceConstant instance,
  ) {
    final result = <String, dynamic>{};
    for (var item in instance.fieldValues.entries) {
      result[item.key.canonicalName.name] = item.value;
    }

    return result;
  }
}

class AnnotationValueGetter extends Visitor<void> {
  AnnotationValueGetter(this.name, this.keys);

  final Map<String, Node> result = <String, Node>{};
  final String name;
  final List<String> keys;

  @override
  void visitConstructorInvocation(ConstructorInvocation annotation) {
    super.visitConstructorInvocation(annotation);
    if (checkName(annotation.target.enclosingClass)) {
      for (final NamedExpression named in annotation.arguments.named) {
        result[named.name] = named.value;
      }
    }
  }

  @override
  void visitConstantExpression(ConstantExpression annotation) {
    super.visitConstantExpression(annotation);
    final Constant constant = annotation.constant;
    if (constant is InstanceConstant && checkName(constant.classNode)) {
      for (final item in constant.fieldValues.entries) {
        final Field field = item.key.node;
        result[field.name.name] = item.value;
      }
    }
  }

  bool checkName(Class klass) => klass.name == name;

  // TODO(liufengkai): Check import URI.
  //      klass.enclosingLibrary.importUri.toString() == 'dart:_internal';

  Node operator [](String name) {
    return result[name];
  }
}

class BinaryPrinterFactory {
  /// Creates new [BinaryPrinter] to write to [targsetSink].
  BinaryPrinter newBinaryPrinter(Sink<List<int>> targetSink) {
    return LimitedBinaryPrinter(targetSink, (_) => true /* predicate */,
        false /* excludeUriToSource */);
  }
}

class DillOps {
  DillOps() {
    printerFactory = BinaryPrinterFactory();
  }

  BinaryPrinterFactory printerFactory;

  Component readComponentFromDill(String dillFile) {
    final Component component = Component();
    final List<int> bytes = File(dillFile).readAsBytesSync();

    BinaryBuilderWithMetadata(bytes).readComponent(component);
    return component;
  }

  Future<void> writeDillFile(Component component, String filename,
      {bool filterExternal = false}) async {
    final IOSink sink = File(filename).openWrite();
    final BinaryPrinter printer = filterExternal
        ? LimitedBinaryPrinter(
            sink,
            // ignore: DEPRECATED_MEMBER_USE
            (Library lib) => true,
            true /* excludeUriToSource */)
        : printerFactory.newBinaryPrinter(sink);

    component.libraries.sort((Library l1, Library l2) {
      return '${l1.fileUri}'.compareTo('${l2.fileUri}');
    });

    component.computeCanonicalNames();
    for (Library library in component.libraries) {
      library.additionalExports.sort((Reference r1, Reference r2) {
        return '${r1.canonicalName}'.compareTo('${r2.canonicalName}');
      });
    }

    printer.writeComponentFile(component);
    await sink.close();
  }
}
