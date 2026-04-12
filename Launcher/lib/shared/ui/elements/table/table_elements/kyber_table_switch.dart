import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:tinycolor2/tinycolor2.dart';

class KyberTableSwitch extends StatefulWidget {
  const KyberTableSwitch({
    required this.onChanged,
    required this.hover,
    super.key,
    this.disabledText,
    this.enabledText,
    this.value,
  });

  final ValueChanged<bool>? onChanged;
  final bool? value;
  final bool hover;
  final String? disabledText;
  final String? enabledText;

  @override
  State<KyberTableSwitch> createState() => _KyberTableSwitchState();
}

class _KyberTableSwitchState extends State<KyberTableSwitch> {
  late bool isActive;

  @override
  void initState() {
    isActive = widget.value ?? false;
    super.initState();
  }

  bool get disabled => widget.onChanged == null;

  @override
  void didChangeDependencies() {
    setState(() {});
    super.didChangeDependencies();
  }

  void onClick() => widget.onChanged!(!widget.value!);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: buildItem(
              widget.disabledText ?? 'OFF',
              widget.value == false,
              false,
            ),
          ),
          Expanded(
            child: buildItem(
              widget.enabledText ?? 'ON',
              widget.value == true,
              true,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildItem(String text, bool enabled, bool nextValue) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : () => widget.onChanged?.call(nextValue),
      child: MouseRegion(
        cursor: disabled ? MouseCursor.defer : SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Duration(milliseconds: enabled ? 100 : 20),
          decoration: BoxDecoration(
            color: enabled
                ? widget.hover && !disabled
                      ? kActiveColor
                      : kWhiteColor.withOpacity(disabled ? .7 : 1)
                : null,
            borderRadius: BorderRadius.circular(2),
            boxShadow: enabled && widget.hover && !disabled
                ? [
                    BoxShadow(
                      color: kActiveColor.withOpacity(.8),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              text.toUpperCase(),
              style: FluentTheme.of(context).typography.body!.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                shadows: widget.hover && !disabled && !enabled
                    ? [
                        Shadow(
                          color: kActiveColor.withOpacity(.8),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
                color: enabled
                    ? widget.hover && !disabled
                          ? Colors.black.mix(kActiveColor, 35)
                          : Colors.black
                    : widget.hover
                    ? kActiveColor
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
