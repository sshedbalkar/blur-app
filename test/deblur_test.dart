// Needs the native engine built first; see AGENTS.md, Validation.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:blur_app/core/feature/feature.dart';
import 'package:blur_app/core/settings/app_settings.dart';
import 'package:blur_app/features/deblur/deblur_feature.dart';
import 'package:blur_app/features/deblur/deblur_native.dart';
import 'package:flutter_test/flutter_test.dart';

const size = 96;

/// Greyscale test picture: blocks of random brightness, so it has plenty of
/// hard edges for blur to destroy.
Float64List blocks() {
  final rng = Random(7);
  final img = Float64List(size * size);
  const block = 8;
  for (var by = 0; by < size; by += block) {
    for (var bx = 0; bx < size; bx += block) {
      final v = 40 + rng.nextInt(176).toDouble();
      for (var y = by; y < by + block; y++) {
        for (var x = bx; x < bx + block; x++) {
          img[y * size + x] = v;
        }
      }
    }
  }
  return img;
}

/// Convolves with the kernel given as (dx, dy) offsets of equal weight.
Float64List blur(Float64List img, List<(int, int)> offsets) {
  final out = Float64List(size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var sum = 0.0;
      for (final (dx, dy) in offsets) {
        final sx = (x + dx).clamp(0, size - 1);
        final sy = (y + dy).clamp(0, size - 1);
        sum += img[sy * size + sx];
      }
      out[y * size + x] = sum / offsets.length;
    }
  }
  return out;
}

void writePgm(String path, Float64List img) {
  final header = 'P5\n$size $size\n255\n'.codeUnits;
  final bytes = Uint8List(header.length + img.length)..setAll(0, header);
  for (var i = 0; i < img.length; i++) {
    bytes[header.length + i] = img[i].round().clamp(0, 255);
  }
  File(path).writeAsBytesSync(bytes);
}

Float64List readPgm(String path) {
  final bytes = File(path).readAsBytesSync();
  // Pixel data is the last size*size bytes, after the text header.
  final pixels = bytes.sublist(bytes.length - size * size);
  return Float64List.fromList([for (final b in pixels) b.toDouble()]);
}

/// Mean squared error over the interior, away from edge effects.
double mse(Float64List a, Float64List b) {
  const margin = 12;
  var sum = 0.0;
  var n = 0;
  for (var y = margin; y < size - margin; y++) {
    for (var x = margin; x < size - margin; x++) {
      final d = a[y * size + x] - b[y * size + x];
      sum += d * d;
      n++;
    }
  }
  return sum / n;
}

void main() {
  late Directory tmp;
  late String input;
  late String output;
  final feature = DeblurFeature(AppSettings.defaults({'HOME': '/nonexistent'}));
  final sharp = blocks();

  setUpAll(() {
    if (!File(nativeLibraryPath()).existsSync()) {
      fail(
        'Native engine not built at ${nativeLibraryPath()}. '
        'Build it first; see AGENTS.md, Validation.',
      );
    }
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('blur_app_deblur');
    input = '${tmp.path}/in.pgm';
    output = '${tmp.path}/out.pgm';
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<FeatureResult> run(Map<String, Object?> params) => FeatureCommand(
    feature,
    params,
  ).run(FeatureContext(inputPath: input, outputPath: output));

  test('motion deconvolution recovers a horizontally smeared image', () async {
    final blurred = blur(sharp, [for (var d = -4; d <= 4; d++) (d, 0)]);
    writePgm(input, blurred);
    final result = await run({
      'method': 'motion',
      'radius': 9,
      'angle': 0,
      'strength': 60,
    });
    expect(result.error, isNull);
    final before = mse(blurred, sharp);
    final after = mse(readPgm(output), sharp);
    expect(after, lessThan(before * 0.5), reason: 'before $before');
  });

  test('motion angle matters: wrong direction does not recover', () async {
    final blurred = blur(sharp, [for (var d = -4; d <= 4; d++) (0, d)]);
    writePgm(input, blurred);
    await run({'method': 'motion', 'radius': 9, 'angle': 90, 'strength': 60});
    final right = mse(readPgm(output), sharp);
    await run({'method': 'motion', 'radius': 9, 'angle': 0, 'strength': 60});
    final wrong = mse(readPgm(output), sharp);
    expect(right, lessThan(wrong * 0.5));
  });

  test('focus deconvolution recovers a disk-blurred image', () async {
    const r = 3;
    final disk = [
      for (var dy = -r; dy <= r; dy++)
        for (var dx = -r; dx <= r; dx++)
          if (dx * dx + dy * dy <= r * r) (dx, dy),
    ];
    final blurred = blur(sharp, disk);
    writePgm(input, blurred);
    final result = await run({'method': 'focus', 'radius': 3, 'strength': 60});
    expect(result.error, isNull);
    final before = mse(blurred, sharp);
    final after = mse(readPgm(output), sharp);
    expect(after, lessThan(before * 0.5), reason: 'before $before');
  });

  test('sharpen moves a softened image closer to the original', () async {
    final blurred = blur(sharp, [
      for (var dy = -1; dy <= 1; dy++)
        for (var dx = -1; dx <= 1; dx++) (dx, dy),
    ]);
    writePgm(input, blurred);
    final result = await run({
      'method': 'sharpen',
      'radius': 1.5,
      'strength': 25,
    });
    expect(result.error, isNull);
    expect(mse(readPgm(output), sharp), lessThan(mse(blurred, sharp)));
  });

  test('strength 0 sharpen leaves the image unchanged', () async {
    writePgm(input, sharp);
    await run({'method': 'sharpen', 'strength': 0});
    expect(mse(readPgm(output), sharp), 0);
  });

  test('colour image with transparency keeps its alpha channel', () async {
    const n = 16;
    final header =
        'P7\nWIDTH $n\nHEIGHT $n\nDEPTH 4\nMAXVAL 255\n'
                'TUPLTYPE RGB_ALPHA\nENDHDR\n'
            .codeUnits;
    final rng = Random(3);
    final pixels = Uint8List.fromList([
      for (var i = 0; i < n * n * 4; i++) rng.nextInt(256),
    ]);
    final rgbaIn = '${tmp.path}/in.pam';
    final rgbaOut = '${tmp.path}/out.pam';
    File(rgbaIn).writeAsBytesSync([...header, ...pixels]);

    final result = await FeatureCommand(feature, {
      'method': 'focus',
      'radius': 2,
    }).run(FeatureContext(inputPath: rgbaIn, outputPath: rgbaOut));
    expect(result.error, isNull);

    final out = File(rgbaOut).readAsBytesSync();
    final outPixels = out.sublist(out.length - n * n * 4);
    var colourChanged = false;
    for (var i = 0; i < outPixels.length; i++) {
      if (i % 4 == 3) {
        expect(outPixels[i], pixels[i], reason: 'alpha at $i');
      } else if (outPixels[i] != pixels[i]) {
        colourChanged = true;
      }
    }
    expect(colourChanged, isTrue);
  });

  test('missing input and unsupported output format report errors', () async {
    final missing = await run({});
    expect(missing.isOk, isFalse);
    expect(missing.error, contains('Cannot read image'));

    writePgm(input, sharp);
    final badFormat = await FeatureCommand(
      feature,
    ).run(FeatureContext(inputPath: input, outputPath: '${tmp.path}/out.nope'));
    expect(badFormat.isOk, isFalse);
    expect(File('${tmp.path}/out.nope').existsSync(), isFalse);
  });
}
