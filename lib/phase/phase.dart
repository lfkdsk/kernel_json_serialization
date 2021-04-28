import 'dart:developer';

import 'package:kernel/ast.dart';
import 'package:kernel/visitor.dart';

export 'kernel_helper.dart';

enum TransformerType {
  DEBUG,
  RELEASE,
  PROFILE,
}

enum EnableType {
  LIB,
  CORE,
}

abstract class TransformerPass extends Transformer {
  Future<void> transform(Component component) {
    visitComponent(component);
  }

  String name();

  Set<TransformerType> types() {
    // ignore: prefer_collection_literals
    return <TransformerType>[
      TransformerType.DEBUG,
      TransformerType.RELEASE,
      TransformerType.PROFILE,
    ].toSet();
  }

  EnableType type() => EnableType.LIB;

  bool defaultEnable() => false;
}

abstract class TransformerPhase extends TransformerPass {
  @override
  Future<void> transform(Component component) {
//    return Future.sync(() {
//      transformerPasses.where((TransformerPass pass) => pass != null).forEach(
//            (TransformerPass pass) async => await pass.transform(component),
//          );
//      return component;
//    });
    return Future.wait(
      transformerPasses
          .where((TransformerPass pass) => pass != null)
          .map((pass) => pass.transform(component))
          .toList(),
    );
  }

  List<TransformerPass> get transformerPasses;
}

class GlobalTransformerPhase extends TransformerPhase {
  @override
  final List<TransformerPass> transformerPasses = [];
  final Component platformStrong;

  GlobalTransformerPhase(this.platformStrong);

  void addTransPass(TransformerPass pass) {
    if (transformerPasses.contains(pass)) {
      return;
    }
    return transformerPasses.add(pass);
  }

  @override
  String name() => 'GlobalPhase';
}
