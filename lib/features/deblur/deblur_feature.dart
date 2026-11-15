import 'dart:isolate';

import '../../core/feature/feature.dart';
import '../../core/settings/app_settings.dart';
import 'deblur_native.dart';
import 'neural_models.dart';

/// Removes blur from a still image, with classical methods or a neural
/// model. The heavy work is done by the native engine on a background
/// isolate.
class DeblurFeature implements Feature {
  DeblurFeature(this.settings);

  /// Read at run time for the neural model folder and choice.
  final AppSettings settings;

  /// The classical methods, in the order of the method numbers in
  /// native/blur_native.cpp.
  static const classicalMethods = ['sharpen', 'focus', 'motion'];
  static const neural = 'neural';
  static const methods = [...classicalMethods, neural];

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
      'direction; '
      '"neural" for heavy or irregular real-world blur when the blur size '
      'and direction are not known (uses an AI model; slower; ignores the '
      'other settings).';

  @override
  List<ParamSpec> get params => const [
    ChoiceParam(
      id: 'method',
      label: 'Method',
      help:
          'sharpen: general softness. focus: out-of-focus blur. '
          'motion: straight-line motion blur. neural: AI model for heavy or '
          'irregular blur; ignores the settings below.',
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
    final inputPath = context.inputPath;
    final outputPath = context.outputPath;
    if (params['method'] == neural) return _runNeural(inputPath, outputPath);

    final method = classicalMethods.indexOf(params['method'] as String);
    final radius = params['radius'] as double;
    final angle = params['angle'] as double;
    final strength = params['strength'] as double;

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

  Future<FeatureResult> _runNeural(String inputPath, String outputPath) async {
    final String modelPath;
    try {
      modelPath = resolveModelPath(settings);
    } on NeuralModelException catch (e) {
      return FeatureResult.failed(e.message);
    }
    final result = await Isolate.run(
      () => neuralDeblurNative(
        inputPath: inputPath,
        outputPath: outputPath,
        modelPath: modelPath,
      ),
    );
    if (result.error != null) return FeatureResult.failed(result.error!);
    final device = result.device!;
    return FeatureResult.ok(
      outputPath,
      note: device.startsWith('cpu: ')
          ? 'The neural model ran on the processor, which is much slower, '
                'because ${device.substring(5)}.'
          : null,
    );
  }
}
