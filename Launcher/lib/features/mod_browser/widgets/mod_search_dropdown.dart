import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as mt;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/features/mod_browser/providers/mod_search_cubit.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/elements/list/kyber_list.dart';
import 'package:kyber_launcher/shared/ui/utils/background_blur.dart';

final filterDropdownKey = GlobalKey();

class ModSearchDropdown extends StatefulWidget {
  const ModSearchDropdown({
    super.key,
  });

  @override
  State<StatefulWidget> createState() => ModSearchDropdownState();
}

class ModSearchDropdownState extends State<ModSearchDropdown> {
  final OverlayPortalController _tooltipController = OverlayPortalController();

  final _link = LayerLink();

  double? _buttonWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocListener<ModSearchCubit, SearchState>(
      listener: (context, state) {
        if (state is! SearchLoaded &&
            state is! SearchLoading &&
            state is! SearchError) {
          if (_tooltipController.isShowing) {
            _tooltipController.hide();
            return;
          }
        }

        if (!_tooltipController.isShowing) {
          _buttonWidth = filterDropdownKey.currentContext?.size?.width;
          _tooltipController.show();
        }
      },
      child: CompositedTransformTarget(
        link: _link,
        child: Container(
          alignment: Alignment.center,
          color: Colors.black.withOpacity(.4),
          child: mt.TextFormField(
            style: const mt.TextStyle(
              fontFamily: FontFamily.battlefrontUI,
              fontSize: 16,
              height: 1,
            ),
            onChanged: (value) => context.read<ModSearchCubit>().search(value),
            decoration: mt.InputDecoration(
              suffix: const Icon(
                mt.Icons.search,
                color: kInactiveColor,
                size: 15,
              ),
              errorStyle: const TextStyle(
                fontFamily: FontFamily.battlefrontUI,
                fontSize: 14,
              ),
              isDense: true,
              border: mt.InputBorder.none,
              enabledBorder: mt.InputBorder.none,
              focusedBorder: mt.InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
              ),
              hintText: l10n.text('common.searchPlaceholder'),
              hintStyle: const TextStyle(
                color: kInactiveColor,
                fontFamily: FontFamily.battlefrontUI,
                fontSize: 16,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MenuWidget extends StatelessWidget {
  const MenuWidget({
    super.key,
    this.width,
  });

  final double? width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: BackgroundBlur(
        borderRadius: BorderRadius.circular(2),
        blurColorOpacity: 0.6,
        blurIntensity: 8,
        child: Container(
          width: width ?? 200,
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: ShapeDecoration(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(2),
            ),
            shadows: const [
              BoxShadow(
                color: Color(0x11000000),
                blurRadius: 32,
                offset: Offset(0, 20),
                spreadRadius: -8,
              ),
            ],
          ),
          child: BlocBuilder<ModSearchCubit, SearchState>(
            builder: (context, state) {
              if (state is SearchLoading) {
                return const Center(
                  child: ProgressRing(),
                );
              }

              if (state is SearchError) {
                return Center(
                  child: Text(
                    state.error,
                    style: const TextStyle(
                      fontFamily: FontFamily.battlefrontUI,
                      fontSize: 18,
                      color: kWhiteColor,
                    ),
                  ),
                );
              }

              if (state is! SearchLoaded) {
                return const SizedBox();
              }

              if (state.results.isEmpty) {
                return Center(
                  child: Text(
                    context.l10n.text('mods.noModsFound'),
                    style: const TextStyle(
                      fontFamily: FontFamily.battlefrontUI,
                      fontSize: 18,
                      color: kWhiteColor,
                    ),
                  ),
                );
              }

              return KyberList(
                activeIndex: -1,
                itemPadding: EdgeInsets.zero,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: state.results.length,
                onSelectionChanged: (value) {
                  final mod = state.results[value];
                  router.push('/mods/mod_browser/${mod.modId}');
                },
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  final mod = state.results[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mod.name,
                          style: const TextStyle(
                            fontFamily: FontFamily.battlefrontUI,
                            fontSize: 18,
                            height: 1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: decoColor,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(50),
                                child: CachedNetworkImage(
                                  imageUrl: mod.uploader.avatar,
                                  height: 15,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              mod.author ?? mod.uploader.name,
                              style: const TextStyle(
                                fontFamily: FontFamily.battlefrontUI,
                                fontSize: 15,
                                color: kWhiteColor,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
