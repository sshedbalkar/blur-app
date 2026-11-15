import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../core/settings/app_settings.dart';

/// A neural model the app knows how to fetch, and why it suggests it.
class NeuralModel {
  const NeuralModel({
    required this.name,
    required this.fileName,
    required this.url,
    required this.sha256,
    required this.bytes,
    required this.reason,
  });

  final String name;
  final String fileName;
  final String url;
  final String sha256;
  final int bytes;

  /// Why this model is suggested, in plain language.
  final String reason;

  int get megabytes => (bytes / 1e6).round();
}

/// The model the app recommends for removing blur. Pinned to one revision
/// and checksum so the download is always the file that was tested.
const recommendedDeblurModel = NeuralModel(
  name: 'NAFNet',
  fileName: 'deblurring_nafnet_2025may.onnx',
  url:
      'https://huggingface.co/opencv/deblurring_nafnet/resolve/'
      'f1f255116cdb628a311d2b5749871189a4639d84/'
      'deblurring_nafnet_2025may.onnx',
  sha256: '07263f416febecce10193dd648e950b22e397cf521eedab1a114ef77b2bc9587',
  bytes: 91736251,
  reason:
      'It removes camera-shake and motion blur without being told the blur '
      'size or direction, is a small download, and fits on an 8 GB graphics '
      'card.',
);

/// What the Settings screen shows next to the download button.
String get deblurModelRecommendation =>
    'Recommended for removing blur: ${recommendedDeblurModel.name} '
    '(${recommendedDeblurModel.megabytes} MB). '
    '${recommendedDeblurModel.reason}';

class NeuralModelException implements Exception {
  NeuralModelException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// File names of the `.onnx` models in [directory], sorted.
List<String> installedModels(String directory) {
  final dir = Directory(directory);
  if (!dir.existsSync()) return [];
  return [
    for (final entry in dir.listSync())
      if (entry is File && entry.path.endsWith('.onnx'))
        entry.uri.pathSegments.last,
  ]..sort();
}

/// Path of the model a neural run should use: the one chosen in settings,
/// else the recommended one if installed, else the first installed.
String resolveModelPath(AppSettings settings) {
  final directory = settings.modelDirectory;
  final chosen = settings.neuralModel;
  if (chosen.isNotEmpty) {
    final path = '$directory/$chosen';
    if (!File(path).existsSync()) {
      throw NeuralModelException(
        'Neural model "$chosen" was not found in $directory. '
        'Choose another in Settings.',
      );
    }
    return path;
  }
  final installed = installedModels(directory);
  if (installed.isEmpty) {
    throw NeuralModelException(
      'No neural model is installed. Download one in Settings.',
    );
  }
  final recommended = recommendedDeblurModel.fileName;
  return '$directory/${installed.contains(recommended) ? recommended : installed.first}';
}

/// Downloads [model] into [directory], reporting progress as 0..1. The file
/// only appears under its final name once its checksum has been verified.
Future<void> downloadModel(
  NeuralModel model,
  String directory, {
  http.Client? client,
  void Function(double fraction)? onProgress,
}) async {
  final ownClient = client == null;
  final httpClient = client ?? http.Client();
  final partial = File('$directory/${model.fileName}.part');
  try {
    Directory(directory).createSync(recursive: true);
    final response = await httpClient.send(
      http.Request('GET', Uri.parse(model.url)),
    );
    if (response.statusCode != 200) {
      throw NeuralModelException(
        'Could not download ${model.name}: the server answered '
        '${response.statusCode}.',
      );
    }
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    final file = partial.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        file.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call((received / model.bytes).clamp(0, 1).toDouble());
      }
    } finally {
      await file.close();
    }
    hasher.close();
    if (digestSink.value.toString() != model.sha256) {
      throw NeuralModelException(
        'The downloaded ${model.name} file is damaged or not the expected '
        'version. Try again.',
      );
    }
    partial.renameSync('$directory/${model.fileName}');
  } on NeuralModelException {
    rethrow;
  } on Exception catch (e) {
    throw NeuralModelException('Could not download ${model.name} ($e)');
  } finally {
    if (partial.existsSync()) partial.deleteSync();
    if (ownClient) httpClient.close();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
