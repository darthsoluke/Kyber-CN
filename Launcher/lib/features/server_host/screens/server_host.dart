import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as mt;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/features/kyber/providers/kyber_status_cubit.dart';
import 'package:kyber_launcher/features/server_browser/widgets/server_info_box/server_info_box.dart';
import 'package:kyber_launcher/features/server_host/providers/host_search_cubit.dart';
import 'package:kyber_launcher/features/server_host/widgets/create_server/map_rotation_page.dart';
import 'package:kyber_launcher/features/server_host/widgets/create_server/mod_collection_selector.dart';
import 'package:kyber_launcher/features/server_host/widgets/hosting_default_card.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/server_settings_box.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_cubit.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_servers_cubit.dart';
import 'package:kyber_launcher/features/server_moderation/screens/moderation_server_list.dart';
import 'package:kyber_launcher/features/server_moderation/screens/server_moderation.dart';
import 'package:kyber_launcher/features/tutorial/models/tutorials/server_host_tutorial.dart';
import 'package:kyber_launcher/gen/assets.gen.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/elements/kyber_input.dart';
import 'package:kyber_launcher/shared/ui/elements/kyber_tab_bar.dart';
import 'package:kyber_launcher/shared/ui/layout/bordered_content.dart';
import 'package:logging/logging.dart';

class ServerHost extends StatefulWidget {
  const ServerHost({super.key, this.initialPage, this.lanOnly = false});

  final int? initialPage;
  final bool lanOnly;

  @override
  State<ServerHost> createState() => _ServerHostState();
}

final TextEditingController searchController = TextEditingController();

class _ServerHostState extends State<ServerHost> {
  late int _currentPage;
  bool showClose = false;
  bool createServer = false;

  @override
  void initState() {
    _currentPage = widget.initialPage ?? 0;
    createServer = widget.lanOnly;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocListener<KyberStatusCubit, KyberStatusState>(
      listenWhen: (previous, current) =>
          previous is! KyberStatusHosting && current is KyberStatusHosting ||
          previous is KyberStatusHosting && current is! KyberStatusHosting,
      listener: (context, state) {
        if (widget.lanOnly) {
          return;
        }

        if (state is KyberStatusHosting) {
          Logger(
            'server_host',
          ).info('Detected hosting status (${state.serverState.id})');
          setState(() => createServer = false);
          context.read<ModerationCubit>().selectServer(
            serverId: state.serverState.id,
          );
        } else {
          context.read<ModerationCubit>().unloadServer();
        }
      },
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: BorderedContent(
              overlappingBorder:
                  !widget.lanOnly &&
                  !createServer &&
                  !context.watch<ModerationCubit>().state.selected,
              header: BlocBuilder<ModerationCubit, ModerationServerState>(
                builder: (context, state) {
                  return Row(
                    children: [
                      if (!widget.lanOnly &&
                          !createServer &&
                          !state.selected) ...[
                        KyberButton(
                          icon: const Icon(mt.Icons.add),
                          text: l10n.text('common.new'),
                          onPressed: () {
                            setState(() => createServer = true);
                          },
                        ),
                        const SizedBox(width: 15),
                        SizedBox(
                          width: 80,
                          child: KyberTabBar(
                            tabs: [
                              SizedBox(
                                height: 17,
                                child: Assets.icons.kblSwap.svg(
                                  color: kWhiteColor,
                                ),
                              ),
                              SizedBox(
                                height: 17,
                                child: Assets.icons.kblFilter.svg(
                                  color: kWhiteColor,
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == 0) {
                                context
                                    .read<ModerationServersCubit>()
                                    .loadServers();
                              }
                            },
                            selectedIndex: -1,
                          ),
                        ),
                        const SizedBox(width: 15),
                      ],
                      if (!widget.lanOnly && state.selected) ...[
                        SizedBox(
                          width: 250,
                          child: KyberTabBar(
                            tabs: [
                              Text(l10n.text('host.moderate')),
                              Text(l10n.text('host.manage')),
                            ],
                            onChanged: (selectedIndex) {
                              context.read<HostSearchCubit>().clear();
                              setState(
                                () => _currentPage = selectedIndex,
                              );
                            },
                            selectedIndex: _currentPage,
                          ),
                        ),
                        const SizedBox(width: 15),
                      ],
                      if (createServer) ...[
                        SizedBox(
                          width: 250,
                          child: KyberTabBar(
                            tabs: [
                              Text(l10n.text('host.rotation')),
                              Text(l10n.text('common.mods')),
                            ],
                            onChanged: (selectedIndex) {
                              context.read<HostSearchCubit>().clear();
                              setState(
                                () => _currentPage = selectedIndex,
                              );
                              if (selectedIndex == 2) {
                                context
                                    .read<ModerationServersCubit>()
                                    .loadServers();
                              }
                              /*showKyberDialog(
                                          context: context,
                                          builder: (_) => BlocProvider.value(
                                            value: context.read<HostSearchCubit>(),
                                            child: LoadMapDialog(),
                                          ),
                                        );*/
                            },
                            selectedIndex: _currentPage,
                          ),
                        ),
                        const SizedBox(width: 15),
                      ],
                      Expanded(
                        child: KyberInput(
                          placeholder: l10n.text('host.searchPlaceholder'),
                          controller: searchController,
                          onChanged: context
                              .read<HostSearchCubit>()
                              .addSearchQuery,
                        ),
                      ),
                      if (!widget.lanOnly &&
                          (createServer || state.selected)) ...[
                        const SizedBox(width: 15),
                        SizedBox(
                          height: 33,
                          width: 33,
                          child: KyberTabBar(
                            onChanged: (index) {
                              setState(() => _currentPage = 0);
                              state.selected
                                  ? context
                                        .read<ModerationCubit>()
                                        .unloadServer()
                                  : setState(
                                      () => createServer = false,
                                    );
                            },
                            selectedIndex: -1,
                            tabs: const [
                              Icon(mt.Icons.close),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              content: BlocBuilder<ModerationCubit, ModerationServerState>(
                builder: (context, state) {
                  if (createServer) {
                    return [
                      const MapRotationPage(),
                      const ModCollectionSelector(),
                    ][_currentPage];
                  }

                  if (widget.lanOnly) {
                    return [
                      const MapRotationPage(),
                      const ModCollectionSelector(),
                    ][_currentPage];
                  }

                  if (state.selected) {
                    return ServerModeration(
                      selectedPage: _currentPage,
                    );
                  }

                  return const ModerationServerList();
                },
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 3,
            child: BlocBuilder<ModerationCubit, ModerationServerState>(
              builder: (context, state) {
                if (createServer) {
                  return ServerSettingsBox(
                    lanOnly: widget.lanOnly,
                    key: ServerHostTutorial.serverSettingsKey,
                  );
                }

                if (state.selected) {
                  return ServerSettingsBox(
                    key: ServerHostTutorial.serverSettingsKey,
                  );
                }

                if (state.server != null) {
                  return ServerInfoBox(
                    server: state.server!,
                    onClose: () =>
                        context.read<ModerationCubit>().unloadServer(),
                    onServerSelected: () =>
                        context.read<ModerationCubit>().selectServer(),
                  );
                }

                return const HostingDefaultCard();
              },
            ),
          ),
        ],
      ),
    );
  }
}
