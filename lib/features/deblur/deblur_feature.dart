import 'dart:isolate';

import '../../core/feature/feature.dart';
import 'deblur_native.dart';

/// Removes blur from a still image using classical methods. The heavy work
/// is done by the native engine on a background isolate.
class DeblurFeature implements Feature {
  /// Order matches the method numbers in native/blur_native.cpp.
  static const methods = ['sharpen', 'focus', 'motion'];

  @override
  String get id => 'deblur';

  @override
  String get name => 'Remove blur';

  @override
  String get description =>
      'Removes blur from a still image. Methods: '
      '"sharpen" for mild softness or when the cause of blur is unknown '
      '(safest); '
      '"focus" for out-of-focus (defocus) blur; '
      '"motion" for blur from camera shake or a moving subject in one '
      'direction.';

  @override
  List<ParamSpec> get params => const [
    ChoiceParam(
      id: 'method',
      label: 'Method',
      help:
          'sharpen: general softness. focus: out-of-focus blur. '
          'motion: straight-line motion blur.',
      options: methods,
      defaultValue: 'sharpen',
    ),
    NumParam(
      id: 'radius',
      label: 'Blur size (px)',
      help:
          'How large the blur is, in pixels. For motion, the length of the '
          'smear. Larger images and heavier blur need larger values.',
      min: 0.5,
      max: 50,
      step: 0.5,
      defaultValue: 3,
    ),
    NumParam(
      id: 'angle',
      label: 'Motion angle (°)',
      help:
          'Direction of the motion smear: 0 is horizontal, 90 is vertical. '
          'Only used by the motion method.',
      min: 0,
      max: 180,
      step: 1,
      defaultValue: 0,
    ),
    NumParam(
      id: 'strength',
      label: 'Strength',
      help:
          'How hard to push the correction. Higher recovers more detail but '
          'can add noise and halos.',
      min: 0,
      max: 100,
      step: 1,
      defaultValue: 50,
    ),
  ];

  @override
  Future<FeatureResult> run(
    FeatureContext context,
    Map<String, Object> params,
  ) async {
    final method = methods.indexOf(params['method'] as String);
    final radius = params['radius'] as double;
    final angle = params['angle'] as double;
    final strength = params['strength'] as double;
    final inputPath = context.inputPath;
    final outputPath = context.outputPath;

    final error = await Isolate.run(
      () => deblurNative(
        inputPath: inputPath,
        outputPath: outputPath,
        method: method,
        radius: radius,
        angle: angle,
        strength: strength,
      ),
    );
    return error == null
        ? FeatureResult.ok(outputPath)
        : FeatureResult.failed(error);
  }
}
