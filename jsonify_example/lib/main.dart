import 'package:just_jsonify_annotation/jsonify_annotation.dart';

@JsonAble()
class Inner with JsonModel<Inner> {
  bool inner;

  Inner({this.inner});

  static createInner() => Inner();
}

@JsonAble()
class Response with JsonModel<Response> {
  int code;
  @JsonProperty(name: 'msg', toJson: encode, nullable: true)
  String message;

  Inner inner;

  Response({this.code, this.message, this.inner});

  @pragma('vm:entry-point')
  static String encode(String decode) {
    return decode + decode;
  }
}

@JsonAble()
class Annother with JsonModel<Annother> {
  @JsonIgnore()
  int code;
  @JsonProperty(defaultValue: 'ahhhhhh')
  String message;

  Annother({this.code, this.message});
}

@JsonAble()
class Generic<T extends JsonModel<T>> with JsonModel<Generic<T>> {
  final int code;
  @JsonProperty(constructors: [Inner.createInner])
  final T body;

  Generic({this.code, this.body});
}

//@JsonAble()
//class GenericPrimary<T> with JsonModel<GenericPrimary<T>> {
//  final int code;
//  @JsonProperty(toJson: to)
//  final T body;
//
//  GenericPrimary({this.code, this.body});
//
//  @pragma('vm:entry-point')
//  static String to<T>(T body) {
//    if (body is String) {
//      return body;
//    }
//
//    print(body.runtimeType);
//    print(T.toString());
//
//    return 'non-empty';
//  }
//}
//
//@JsonAble()
//class ListModel with JsonModel<ListModel> {
//  ListModel({this.ints, this.inners});
//
//  final List<int> ints;
//  final List<Response> inners;
//}

bool listEquals<T>(List<T> a, List<T> b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (int index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool mapEquals<T, U>(Map<T, U> a, Map<T, U> b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (T key in a.keys) {
    if (b[key] is Map &&
        a[key] is Map &&
        mapEquals(b[key] as Map, a[key] as Map)) {
      continue;
    }

    if (b[key] is List &&
        a[key] is List &&
        listEquals(b[key] as List, a[key] as List)) {
      continue;
    }

    if (!b.containsKey(key) || b[key] != a[key]) {
      return false;
    }
  }
  return true;
}

void expect(String testName, Map actual, Map expected) {
  if (!mapEquals(actual, expected)) {
    print('[Test] $testName error.');
    throw 'Expect Error in with actual: $actual expected: $expected';
  } else {
    print('[Test] $testName passed');
  }
}

void testIt() {
  {
    final Inner inner = Inner(inner: true);
    expect('Simple Test', inner.toJson(), {'inner': true});
  }

  /// JsonAble Recursive.
  {
    final Inner inner = Inner(inner: true);
    final Response res = Response()
      ..code = 200
      ..message = 'message'
      ..inner = inner;
    expect('Recurive Model Test', res.toJson(), {
      'code': 200,
      'msg': 'messagemessage',
      'inner': {'inner': true},
    });
  }

  final Map<String, dynamic> mmp = {};
  mmp['code'] = 100;
  mmp['message'] = 'message';
//    mmp['inner'] = null;
  final Map<String, dynamic> innermmp = {};
  innermmp['inner'] = true;
  mmp['inner'] = innermmp;

  try {
    // ignore: unnecessary_parenthesis
    print(Response().fromJson(mmp).toJson());
    print(Response().fromJson(mmp).code);
  } catch (e, s) {
    print(e);
    print(s);
  }

  final Annother anno = Annother()
    ..code = 100
    ..message = 'fuccccck';
  print(anno.toJson());

  final Annother anno1 = Annother()..code = 100;
  print(anno1.toJson());

  final Map<String, dynamic> annoMap = {};
  annoMap['code'] = 100;
  annoMap['message'] = 'msg';
  print(Annother().fromJson(annoMap).toJson());
  print(Annother().fromJson({'code': 100, 'message': null}).toJson());

//  final GenericInner generic =
//      GenericInner(code: 100, body: Inner(inner: true));
//  print(generic.toJson());

//  final GenericPrimary<String> genericPrimary =
//      GenericPrimary<String>(code: 100, body: 'body');
//  print(genericPrimary.toJson());
//
//  final ListModel listModel = ListModel(ints: [0, 1, 2, 3, 4, 5], inners: [Response(inner: Inner(inner: true)), Response(inner: Inner(inner: false))]);
//  print(json.encode(listModel.toJson()));
}

void main() => testIt();