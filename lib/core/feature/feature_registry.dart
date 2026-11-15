import 'feature.dart';

/// Holds the features available to the app. Features can be registered and
/// removed while the app is running; listeners (the UI) are told on change.
class FeatureRegistry {
  final Map<String, Feature> _features = {};
  final List<void Function()> _listeners = [];

  List<Feature> get all => List.unmodifiable(_features.values);

  Feature? byId(String id) => _features[id];

  void register(Feature feature) {
    if (_features.containsKey(feature.id)) {
      throw ArgumentError('Feature id "${feature.id}" is already registered');
    }
    final ids = <String>{};
    for (final p in feature.params) {
      if (!ids.add(p.id)) {
        throw ArgumentError(
          'Feature "${feature.id}" declares parameter "${p.id}" twice',
        );
      }
    }
    _features[feature.id] = feature;
    _notify();
  }

  void unregister(String id) {
    if (_features.remove(id) != null) _notify();
  }

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}
