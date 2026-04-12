import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as mt;
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/features/maxima/helper/maxima_helper.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/navigation_bar/navigation_bar_list.dart';
import 'package:kyber_launcher/shared/ui/navigation_bar/widgets/navigation_bar_item.dart';
import 'package:kyber_launcher/shared/ui/utils/background_blur.dart';
import 'package:kyber_launcher/shared/ui/utils/button_builder.dart';

final dropdownsKey = GlobalKey();

class PlayDropdown extends StatefulWidget {
  const PlayDropdown({
    required this.onTap,
    required this.entry,
    required this.onHover,
    required this.hover,
    required this.active,
    super.key,
  });

  final Function onTap;
  final Function(bool value) onHover;
  final NavigationBarEntry entry;
  final bool hover;
  final bool active;

  @override
  State<StatefulWidget> createState() => PlayDropdownState();
}

class PlayDropdownState extends State<PlayDropdown> {
  final OverlayPortalController _tooltipController = OverlayPortalController();

  final _link = LayerLink();

  double? _buttonWidth;

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _tooltipController,
        overlayChildBuilder: (BuildContext context) {
          return SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Stack(
              children: [
                ModalBarrier(
                  onDismiss: () {
                    if (_tooltipController.isShowing) {
                      _tooltipController.hide();
                    }
                  },
                ),
                Positioned(
                  width: _buttonWidth,
                  child: CompositedTransformFollower(
                    link: _link,
                    targetAnchor: Alignment.bottomLeft,
                    showWhenUnlinked: false,
                    offset: const Offset(-2, 0),
                    child: Align(
                      alignment: AlignmentDirectional.topStart,
                      child: MenuWidget(
                        width: _buttonWidth,
                        onHide: () {
                          if (_tooltipController.isShowing) {
                            _tooltipController.hide();
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        child: NavigationBarItem(
          item: widget.entry,
          onTap: () async {
            if (widget.active) {
              onTap();
            }

            widget.onTap();
          },
          onHover: (value) => widget.onHover(value),
          active: widget.active,
          hover: widget.hover,
          child: Row(
            children: [
              Icon(
                mt.Icons.arrow_drop_down_outlined,
                size: 18,
                color: widget.hover
                    ? kActiveColor
                    : widget.active
                    ? kWhiteColor
                    : kInactiveColor,
              ),
              const SizedBox(width: 0),
            ],
          ),
        ),
      ),
    );
  }

  void onTap() {
    _buttonWidth = (dropdownsKey.currentContext?.size?.width ?? 0) + 4;
    _tooltipController.toggle();
  }
}

class MenuWidget extends StatelessWidget {
  const MenuWidget({
    required this.onHide,
    super.key,
    this.width,
  });

  final void Function() onHide;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BackgroundBlur(
      borderRadius: BorderRadius.circular(2),
      blurColorOpacity: 0.6,
      blurIntensity: 8,
      child: SizedBox(
        width: 165,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 1,
              color: decoColor,
            ),
            ButtonBuilder(
              onClick: () async {
                onHide();
                await MaximaHelper.requestGameLaunch(context);
              },
              builder: (context, hovered) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: hovered ? kActiveColor : kInactiveColor,
                        width: 2,
                      ),
                      right: BorderSide(
                        color: hovered ? kActiveColor : kInactiveColor,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          color: hovered ? kActiveColor : Colors.white,
                        ),
                        child: Text(
                          l10n.text('nav.launchGame'),
                          style: TextStyle(
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
