import '../core/feature/feature_registry.dart';
import 'deblur/deblur_feature.dart';

/// The single place built-in features are plugged in. To add a feature:
/// implement `Feature` in its own folder under lib/features/ and register it
/// here. No other file needs to change.
void registerBuiltinFeatures(FeatureRegistry registry) {
  registry.register(DeblurFeature());
}
