// Needs the native engine built and, for the last test, the recommended
// model fetched; see AGENTS.md, Validation.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:blur_app/core/feature/feature.dart';
import 'package:blur_app/core/settings/app_settings.dart';
import 'package:blur_app/features/deblur/deblur_feature.dart';
import 'package:blur_app/features/deblur/deblur_native.dart';
import 'package:blur_app/features/deblur/neural_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where AGENTS.md says to put the recommended model and its sample photo.
const realModelDir = 'build/models';
const samplePhoto = '$realModelDir/licenseplate_motion.jpg';
const sampleWidth = 600;
const sampleHeight = 482;

List<int> _varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  return out..add(v);
}

List<int> _bytes(int field, List<int> payload) => [
  ..._varint(field << 3 | 2),
  ..._varint(payload.length),
  ...payload,
];
List<int> _text(int field, String s) => _bytes(field, utf8.encode(s));
List<int> _int(int field, int v) => [..._varint(field << 3), ..._varint(v)];

/// A float tensor of four free dimensions, as an ONNX ValueInfoProto.
List<int> _image(String name) => [
  ..._text(1, name),
  ..._bytes(
    2,
    _bytes(1, [
      ..._int(1, 1), // float32
      ..._bytes(2, [
        for (final d in ['n', 'c', 'h', 'w']) ..._bytes(1, _text(2, d)),
      ]),
    ]),
  ),
];

/// The smallest valid model: output = input. Written by hand in ONNX's
/// protobuf encoding so the engine's tiling, blending and file handling can
/// be tested exactly, without the 92 MB real model.
Uint8List identityModel() => Uint8List.fromList([
  ..._int(1, 8), // ir_version
  ..._bytes(8, _int(2, 13)), // opset 13
  ..._bytes(7, [
    ..._bytes(1, [..._text(1, 'x'), ..._text(2, 'y'), ..._text(4, 'Identity')]),
    ..._text(2, 'g'),
    ..._bytes(11, _image('x')),
    ..._bytes(12, _image('y')),
  ]),
]);

/// Random-noise picture in binary PNM form (P5 grey / P6 colour).
Uint8List noise(int width, int height, int channels, int seed) {
  final rng = Random(seed);
  return Uint8List.fromList([
    for (var i = 0; i < width * height * channels; i++) rng.nextInt(256),
  ]);
}

void writePnm(String path, int width, int height, Uint8List pixels) {
  final magic = pixels.length == width * height ? 'P5' : 'P6';
  File(
    path,
  ).writeAsBytesSync([...'$magic\n$width $height\n255\n'.codeUnits, ...pixels]);
}

Uint8List readPixels(String path, int count) {
  final bytes = File(path).readAsBytesSync();
  return bytes.sublist(bytes.length - count);
}

/// Mean brightness step between horizontal neighbours: higher = sharper.
double sharpness(Uint8List rgb, int width, int height) {
  var sum = 0.0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width - 1; x++) {
      final i = (y * width + x) * 3;
      sum += (rgb[i + 1] - rgb[i + 4]).abs();
    }
  }
  return sum / (height * (width - 1));
}

void main() {
  late Directory tmp;
  late AppSettings settings;
  late DeblurFeature feature;

  setUpAll(() {
    if (!File(nativeLibraryPath()).existsSync()) {
      fail(
        'Native engine not built at ${nativeLibraryPath()}. '
        'Build it first; see AGENTS.md, Validation.',
      );
    }
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('blur_app_neural');
    settings = AppSettings.defaults({'HOME': tmp.path})
      ..modelDirectory = '${tmp.path}/models';
    Directory(settings.modelDirectory).createSync();
    feature = DeblurFeature(settings);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  void installIdentity() =>
      File('${settings.modelDirectory}/identity.onnx')
          .writeAsBytesSync(identityModel());

  Future<FeatureResult> run(String input, String output) => FeatureCommand(
    feature,
    {'method': 'neural'},
  ).run(FeatureContext(inputPath: input, outputPath: output));

  test('small grey image passes through an identity model unchanged', () async {
    installIdentity();
    final pixels = noise(96, 80, 1, 1);
    writePnm('${tmp.path}/in.pgm', 96, 80, pixels);
    final result = await run('${tmp.path}/in.pgm', '${tmp.path}/out.pgm');
    expect(result.error, isNull);
    expect(readPixels('${tmp.path}/out.pgm', pixels.length), pixels);
  });

  test('image larger than a tile is reassembled without seams', () async {
    installIdentity();
    const width = 1100, height = 700;
    final pixels = noise(width, height, 3, 2);
    writePnm('${tmp.path}/in.ppm', width, height, pixels);
    final result = await run('${tmp.path}/in.ppm', '${tmp.path}/out.ppm');
    expect(result.error, isNull);
    expect(readPixels('${tmp.path}/out.ppm', pixels.length), pixels);
  });

  test('transparency is preserved', () async {
    installIdentity();
    const n = 16;
    final header =
        'P7\nWIDTH $n\nHEIGHT $n\nDEPTH 4\nMAXVAL 255\n'
                'TUPLTYPE RGB_ALPHA\nENDHDR\n'
            .codeUnits;
    final pixels = noise(n, n, 4, 3);
    File('${tmp.path}/in.pam').writeAsBytesSync([...header, ...pixels]);
    final result = await run('${tmp.path}/in.pam', '${tmp.path}/out.pam');
    expect(result.error, isNull);
    expect(readPixels('${tmp.path}/out.pam', pixels.length), pixels);
  });

  test('missing, unknown and unusable models report errors', () async {
    writePnm('${tmp.path}/in.pgm', 8, 8, noise(8, 8, 1, 4));
    final none = await run('${tmp.path}/in.pgm', '${tmp.path}/out.pgm');
    expect(
      none.error,
      'No neural model is installed. Download one in Settings.',
    );

    settings.neuralModel = 'gone.onnx';
    final gone = await run('${tmp.path}/in.pgm', '${tmp.path}/out.pgm');
    expect(gone.error, contains('"gone.onnx" was not found'));

    settings.neuralModel = '';
    File('${settings.modelDirectory}/bad.onnx').writeAsStringSync('not onnx');
    final bad = await run('${tmp.path}/in.pgm', '${tmp.path}/out.pgm');
    expect(bad.error, startsWith('The neural model failed: '));
    expect(File('${tmp.path}/out.pgm').existsSync(), isFalse);
  });

  test('recommended model makes the sample blurry photo sharper', () async {
    final model = '$realModelDir/${recommendedDeblurModel.fileName}';
    if (!File(model).existsSync() || !File(samplePhoto).existsSync()) {
      fail(
        'Recommended model or sample photo missing from $realModelDir. '
        'Fetch them first; see AGENTS.md, Validation.',
      );
    }
    settings.modelDirectory = realModelDir;
    const count = sampleWidth * sampleHeight * 3;

    // Strength-0 sharpen changes nothing: it just decodes the JPEG.
    final decoded = await FeatureCommand(feature, {'strength': 0}).run(
      FeatureContext(
        inputPath: samplePhoto,
        outputPath: '${tmp.path}/before.ppm',
      ),
    );
    expect(decoded.error, isNull);
    final result = await run(samplePhoto, '${tmp.path}/after.ppm');
    expect(result.error, isNull);
    // ignore: avoid_print
    print('neural run note: ${result.note ?? 'ran on the GPU'}');

    final before = sharpness(
      readPixels('${tmp.path}/before.ppm', count),
      sampleWidth,
      sampleHeight,
    );
    final after = sharpness(
      readPixels('${tmp.path}/after.ppm', count),
      sampleWidth,
      sampleHeight,
    );
    // Measured gain: about 1.23x.
    expect(after, greaterThan(before * 1.15), reason: 'before $before');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
