import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// FFI binding to `blur_deblur` in native/blur_native.cpp. Keep the
/// signature and the method numbering in sync with that file.
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

  const errLen = 512;
  final input = inputPath.toNativeUtf8();
  final output = outputPath.toNativeUtf8();
  final err = calloc<Uint8>(errLen).cast<Utf8>();
  try {
    final code = deblur(
      input,
      output,
      method,
      radius,
      angle,
      strength,
      err,
      errLen,
    );
    return code == 0 ? null : err.toDartString();
  } finally {
    calloc.free(input);
    calloc.free(output);
    calloc.free(err);
  }
}
