import 'package:collection/collection.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/features/kyber/models/mode.dart';
import 'package:kyber_launcher/features/mods/services/level_declaration_service.dart';
import 'package:kyber_launcher/features/server_host/providers/host_collection_cubit.dart';
import 'package:kyber_launcher/features/server_host/providers/host_search_cubit.dart';
import 'package:kyber_launcher/gen/assets.gen.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/utils/button_builder.dart';

class ModeList extends StatefulWidget {
  const ModeList({required this.onModeSelected, super.key});

  final void Function(Mode selectedMode) onModeSelected;

  @override
  State<ModeList> createState() => _ModeListState();
}

class _ModeListState extends State<ModeList> {
  late List<Mode> filteredModes;

  @override
  void initState() {
    filteredModes = loadModes();
    super.initState();
  }

  List<Mode> loadModes() {
    final collection = context
        .read<HostCollectionCubit>()
        .state
        .selectedModCollection;
    final customModes = sl.get<LevelDeclarationService>().getModesForCollection(
      collection,
      includeDefaults: true,
    );

    return customModes.sorted((a, b) => b.maxPlayers.compareTo(a.maxPlayers));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<HostSearchCubit, HostSearchState>(
      listener: (context, state) {
        final modes = loadModes();
        setState(() {
          filteredModes = modes
              .where((mode) {
                return mode.name.toLowerCase().contains(
                  state.searchQuery.toLowerCase(),
                );
              })
              .sorted((a, b) => b.maxPlayers.compareTo(a.maxPlayers))
              .toList();
        });
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 300,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.4,
        ),
        itemBuilder: (context, index) {
          final item = filteredModes[index];

          return RepaintBoundary(
            key: ValueKey(item.mode),
            child: _ModeEntry(
              onTap: () => widget.onModeSelected(item),
              mode: item,
            ),
          );
        },
        itemCount: filteredModes.length,
      ),
    );
  }
}

class _ModeEntry extends StatelessWidget {
  const _ModeEntry({
    required this.onTap,
    required this.mode,
  });

  final Mode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ButtonBuilder(
      onClick: onTap,
      builder: (context, hovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: hovered ? kActiveColor : decoColor,
              width: 2,
            ),
            color: Colors.black,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              children: [
                Positioned.fill(
                  top: -1,
                  left: -1,
                  right: -1,
                  bottom: -1,
                  child: ShaderMask(
                    shaderCallback: (rect) {
                      return const LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black,
                        ],
                      ).createShader(
                        Rect.fromLTRB(0, 0, rect.width, rect.height),
                      );
                    },
                    blendMode: BlendMode.dstIn,
                    child: mode.image != null
                        ? Image.memory(
                            mode.image!,
                            fit: BoxFit.cover,
                          )
                        : Assets.images.modes.values
                                  .where((x) {
                                    return x.path.contains(mode.mode);
                                  })
                                  .firstOrNull
                                  ?.image(
                                    fit: BoxFit.cover,
                                  ) ??
                              Assets.images.kyberNoImage.image(
                                fit: BoxFit.cover,
                              ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.name,
                        style: const TextStyle(
                          fontFamily: FontFamily.battlefrontUI,
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        decoration: const BoxDecoration(
                          border: Border(
                            top: kDefaultBorder,
                            bottom: kDefaultBorder,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        width: 60,
                        alignment: Alignment.center,
                        child: Text(
                          context.l10n.text(
                            'common.playerCount',
                            params: {
                              'count': mode.maxPlayers == -1
                                  ? '∞'
                                  : mode.maxPlayers.toString(),
                            },
                          ),
                          style: const TextStyle(
                            fontFamily: FontFamily.battlefrontUI,
                            fontSize: 12,
                            color: kButtonBorder,
                            fontWeight: FontWeight.bold,
                            height: 1,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
