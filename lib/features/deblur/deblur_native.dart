import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// FFI bindings to `blur_deblur` and `blur_neural_deblur` in
/// native/blur_native.cpp. Keep the signatures and the method numbering in
/// sync with that file.
typedef _DeblurC = Int32 Function(
  Pointer<Utf8> input,
  Pointer<Utf8> output,
  Int32 method,
  Double radius,
  Double angle,
  Double strength,
  Pointer<Utf8> err,
  Int32 errLen,
);
typedef _DeblurDart = int Function(
  Pointer<Utf8> input,
  Pointer<Utf8> output,
  int method,
  double radius,
  double angle,
  double strength,
  Pointer<Utf8> err,
  int errLen,
);

typedef _NeuralC = Int32 Function(
  Pointer<Utf8> input,
  Pointer<Utf8> output,
  Pointer<Utf8> model,
  Pointer<Utf8> device,
  Int32 deviceLen,
  Pointer<Utf8> err,
  Int32 errLen,
);
typedef _NeuralDart = int Function(
  Pointer<Utf8> input,
  Pointer<Utf8> output,
  Pointer<Utf8> model,
  Pointer<Utf8> device,
  int deviceLen,
  Pointer<Utf8> err,
  int errLen,
);

const _messageLen = 512;

/// Where the native engine lives: inside the app bundle when installed or
/// run with `flutter run`, or the standalone build used by `flutter test`.
String nativeLibraryPath() {
  final bundled =
      '${File(Platform.resolvedExecutable).parent.path}/lib/libblur_native.so';
  return File(bundled).existsSync()
      ? bundled
      : 'build/native/libblur_native.so';
}

/// Runs the native deblur. Returns null on success, or an error message.
/// Blocks until done, so call it from a background isolate.
String? deblurNative({
  required String inputPath,
  required String outputPath,
  required int method,
  required double radius,
  required double angle,
  required double strength,
}) {
  final DynamicLibrary library;
  try {
    library = DynamicLibrary.open(nativeLibraryPath());
  } on ArgumentError catch (e) {
    return 'The image engine could not be loaded (${e.message})';
  }
  final deblur = library.lookupFunction<_DeblurC, _DeblurDart>('blur_deblur');

  final input = inputPath.toNativeUtf8();
  final output = outputPath.toNativeUtf8();
  final err = calloc<Uint8>(_messageLen).cast<Utf8>();
  try {
    final code = deblur(
      input,
      output,
      method,
      radius,
      angle,
      strength,
      err,
      _messageLen,
    );
    return code == 0 ? null : err.toDartString();
  } finally {
    calloc.free(input);
    calloc.free(output);
    calloc.free(err);
  }
}

/// Runs the neural deblur with the model at [modelPath]. On success `error`
/// is null and `device` is "gpu", or "cpu: " followed by why the GPU was not
/// used.
/// Blocks until done, so call it from a background isolate.
({String? error, String? device}) neuralDeblurNative({
  required String inputPath,
  required String outputPath,
  required String modelPath,
}) {
  final DynamicLibrary library;
  try {
    library = DynamicLibrary.open(nativeLibraryPath());
  } on ArgumentError catch (e) {
    return (
      error: 'The image engine could not be loaded (${e.message})',
      device: null,
    );
  }
  final neural = library.lookupFunction<_NeuralC, _NeuralDart>(
    'blur_neural_deblur',
  );

  final input = inputPath.toNativeUtf8();
  final output = outputPath.toNativeUtf8();
  final model = modelPath.toNativeUtf8();
  final device = calloc<Uint8>(_messageLen).cast<Utf8>();
  final err = calloc<Uint8>(_messageLen).cast<Utf8>();
  try {
    final code = neural(
      input,
      output,
      model,
      device,
      _messageLen,
      err,
      _messageLen,
    );
    return code == 0
        ? (error: null, device: device.toDartString())
        : (error: err.toDartString(), device: null);
  } finally {
    calloc.free(input);
    calloc.free(output);
    calloc.free(model);
    calloc.free(device);
    calloc.free(err);
  }
}
