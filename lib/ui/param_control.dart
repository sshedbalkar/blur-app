import 'package:material_ui/material_ui.dart';

import '../core/feature/feature.dart';

/// Renders the right control for a [ParamSpec]. The control itself cannot
/// produce a value outside the spec's supported range.
class ParamControl extends StatelessWidget {
  const ParamControl({
    super.key,
    required this.spec,
    required this.value,
    required this.onChanged,
    required this.onCommitted,
    this.enabled = true,
  });

  final ParamSpec spec;
  final Object value;
  final bool enabled;

  /// Fires continuously while the user adjusts the control.
  final ValueChanged<Object> onChanged;

  /// Fires once when the user settles on a value (used for logging).
  final ValueChanged<Object> onCommitted;

  @override
  Widget build(BuildContext context) {
    final spec = this.spec;
    final control = switch (spec) {
      NumParam() => _number(spec),
      BoolParam() => Switch(
        value: value as bool,
        onChanged: enabled
            ? (v) {
                onChanged(v);
                onCommitted(v);
              }
            : null,
      ),
      ChoiceParam() => DropdownButton<String>(
        value: value as String,
        onChanged: enabled
            ? (v) {
                if (v == null) return;
                onChanged(v);
                onCommitted(v);
              }
            : null,
        items: [
          for (final o in spec.options)
            DropdownMenuItem(value: o, child: Text(o)),
        ],
      ),
    };
    return Tooltip(
      message: spec.help,
      child: Row(
        children: [
          SizedBox(width: 160, child: Text(spec.label)),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: control),
          ),
        ],
      ),
    );
  }

  Widget _number(NumParam spec) {
    final v = value as double;
    final step = spec.step;
    final divisions = step != null && step > 0 && spec.max > spec.min
        ? ((spec.max - spec.min) / step).round()
        : null;
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: v,
            min: spec.min,
            max: spec.max,
            divisions: divisions != null && divisions > 0 ? divisions : null,
            onChanged: enabled && spec.max > spec.min ? onChanged : null,
            onChangeEnd: onCommitted,
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
