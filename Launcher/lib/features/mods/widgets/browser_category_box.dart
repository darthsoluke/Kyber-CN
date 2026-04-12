import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/features/mod_browser/providers/mod_browser_cubit.dart';
import 'package:kyber_launcher/features/nexusmods/services/nexusmods_service.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/elements/list/kyber_list.dart';
import 'package:kyber_launcher/shared/ui/utils/background_blur.dart';

class BrowserCategoryBox extends StatelessWidget {
  const BrowserCategoryBox({
    required this.onCategorySelected,
    required this.selectedCategory,
    super.key,
  });

  final int selectedCategory;
  final void Function(int) onCategorySelected;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ModBrowserCubit, ModBrowserState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(kDefaultOuterBorderRadius),
              ),
              child: BackgroundBlur(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(kDefaultOuterBorderRadius),
                    ),
                    border: Border(
                      top: kDefaultBorder,
                      right: kDefaultBorder,
                      left: kDefaultBorder,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(kDefaultOuterBorderRadius - 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: kDefaultPadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.text('mods.categories.title'),
                                style: const TextStyle(
                                  fontFamily: FontFamily.battlefrontUI,
                                  fontSize: 21,
                                  height: 1,
                                ),
                              ),
                              Text(
                                context.l10n.text(
                                  'mods.categories.description',
                                ),
                                style: const TextStyle(
                                  fontFamily: FontFamily.battlefrontUI,
                                  fontSize: 14,
                                  color: kWhiteColor,
                                  height: 0.9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (sl.get<NexusModsService>().apiToken != null)
              BlocBuilder<ModBrowserCubit, ModBrowserState>(
                builder: (context, state) {
                  return Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(kDefaultOuterBorderRadius),
                      ),
                      child: BackgroundBlur(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(.5),
                                  border: const Border(
                                    bottom: kDefaultBorder,
                                    left: kDefaultBorder,
                                    right: kDefaultBorder,
                                  ),
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(
                                      kDefaultOuterBorderRadius,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: KyberList(
                                      blur: false,
                                      colorOpacity: 0,
                                      physics: const ScrollPhysics(),
                                      shrinkWrap: true,
                                      itemBuilder: (context, index) {
                                        final category = sl<NexusModsService>()
                                            .nexusBridge
                                            .categories[index];

                                        return Text(
                                          category.name.toUpperCase(),
                                          style: const TextStyle(
                                            fontFamily:
                                                FontFamily.battlefrontUI,
                                            fontSize: 16,
                                            height: 1,
                                          ),
                                        );
                                      },
                                      activeIndex: selectedCategory,
                                      itemCount: sl<NexusModsService>()
                                          .nexusBridge
                                          .categories
                                          .length,
                                      onSelectionChanged: onCategorySelected,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
