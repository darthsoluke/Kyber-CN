import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as mt;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/kyber/helper/kyber_status_helper.dart';
import 'package:kyber_launcher/features/kyber/providers/kyber_api_status_cubit.dart';
import 'package:kyber_launcher/features/lightswitch/models/status.dart';
import 'package:kyber_launcher/features/server_browser/constants/modes.dart';
import 'package:kyber_launcher/features/server_browser/dialogs/lan_direct_connect_dialog.dart';
import 'package:kyber_launcher/features/server_browser/helpers/lan_server_helper.dart';
import 'package:kyber_launcher/features/server_browser/models/server_filter.dart';
import 'package:kyber_launcher/features/server_browser/models/server_list_state.dart';
import 'package:kyber_launcher/features/server_browser/providers/lan_server_list_cubit.dart';
import 'package:kyber_launcher/features/server_browser/providers/server_browser_cubit.dart';
import 'package:kyber_launcher/features/server_browser/providers/server_list_cubit.dart';
import 'package:kyber_launcher/features/server_browser/widgets/event_list.dart';
import 'package:kyber_launcher/features/server_browser/widgets/lan_server_list_widget.dart';
import 'package:kyber_launcher/features/server_browser/widgets/server_info_box/server_info_box.dart';
import 'package:kyber_launcher/features/server_browser/widgets/server_list/server_list.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/elements/filter_dropdown.dart';
import 'package:kyber_launcher/shared/ui/layout/bordered_content.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class ServerBrowser extends StatefulWidget {
  const ServerBrowser({super.key, this.lanOnly = false});

  final bool lanOnly;

  @override
  State<ServerBrowser> createState() => _ServerBrowserState();
}

class _ServerBrowserState extends State<ServerBrowser> {
  late int _sourceIndex;

  bool get _showLanLobby => widget.lanOnly || _sourceIndex == 1;

  @override
  void initState() {
    _sourceIndex = widget.lanOnly ? 1 : 0;
    super.initState();
  }

  @override
  void didUpdateWidget(covariant ServerBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lanOnly != widget.lanOnly) {
      _sourceIndex = widget.lanOnly ? 1 : 0;
      context.read<ServerBrowserCubit>().clearServer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: BorderedContent(
            overlappingBorder: true,
            header: MultiBlocListener(
              listeners: [
                if (!widget.lanOnly)
                  BlocListener<ServerListCubit, ServerListState>(
                    listener: (context, state) {
                      if (_showLanLobby) {
                        return;
                      }

                      _syncSelectedServer(
                        context,
                        (state as ServerListLoaded).servers,
                      );
                    },
                    listenWhen: (previous, current) =>
                        current is ServerListLoaded,
                  ),
                BlocListener<LanServerListCubit, ServerListState>(
                  listener: (context, state) {
                    if (!_showLanLobby) {
                      return;
                    }

                    _syncSelectedServer(
                      context,
                      (state as ServerListLoaded).servers,
                    );
                  },
                  listenWhen: (previous, current) =>
                      current is ServerListLoaded,
                ),
              ],
              child: _HeaderBar(
                lanOnly: widget.lanOnly,
                sourceIndex: _sourceIndex,
                onSourceChanged: (value) {
                  if (widget.lanOnly) {
                    return;
                  }
                  setState(() => _sourceIndex = value);
                  context.read<ServerBrowserCubit>().clearServer();
                },
              ),
            ),
            content: _showLanLobby
                ? const LanServerListWidget(key: Key('lan_server_list'))
                : const ServerListWidget(key: Key('server_list')),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _StatusWidget(lanOnly: widget.lanOnly),
              BlocBuilder<ServerBrowserCubit, ServerBrowserState>(
                builder: (context, state) {
                  if (state.selectedServer != null) {
                    return Expanded(
                      child: ServerInfoBox(
                        server: state.selectedServer!,
                      ),
                    );
                  }

                  if (widget.lanOnly) {
                    return const _LanBrowserHint();
                  }

                  return const HomeEventList();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _syncSelectedServer(BuildContext context, List<Object> servers) {
    final selectedServer = context
        .read<ServerBrowserCubit>()
        .state
        .selectedServer;
    if (selectedServer == null) {
      return;
    }

    final serverId = selectedServer is ServerGroup
        ? selectedServer.serverInfo.id
        : (selectedServer as Server).id;

    final server = servers.where((s) {
      final id = s is ServerGroup ? s.serverInfo.id : (s as Server).id;
      return id == serverId;
    }).toList();

    if (server.isEmpty) {
      context.read<ServerBrowserCubit>().clearServer();
    }
  }
}

class _LanBrowserHint extends StatelessWidget {
  const _LanBrowserHint();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Expanded(
      child: KyberCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(mt.Icons.wifi_tethering, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      l10n.text('serverBrowser.lanHint.title'),
                      style: const TextStyle(
                        fontFamily: FontFamily.battlefrontUI,
                        fontSize: 21,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const CardSection(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                l10n.text('serverBrowser.lanHint.description'),
                style: const TextStyle(
                  fontFamily: FontFamily.battlefrontUI,
                  fontSize: 15,
                  color: kWhiteColor,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.lanOnly,
    required this.sourceIndex,
    required this.onSourceChanged,
  });

  final bool lanOnly;
  final int sourceIndex;
  final ValueChanged<int> onSourceChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Align(
      child: SizedBox(
        child: Row(
          children: [
            SizedBox(
              width: 190,
              child: lanOnly
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(mt.Icons.wifi_tethering, size: 16),
                        const SizedBox(width: 6),
                        Text(l10n.text('serverBrowser.lan')),
                      ],
                    )
                  : KyberTabBar(
                      tabs: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(mt.Icons.public, size: 16),
                            const SizedBox(width: 6),
                            Text(l10n.text('serverBrowser.online')),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(mt.Icons.wifi_tethering, size: 16),
                            const SizedBox(width: 6),
                            Text(l10n.text('serverBrowser.lan')),
                          ],
                        ),
                      ],
                      onChanged: onSourceChanged,
                      selectedIndex: sourceIndex,
                    ),
            ),
            const SizedBox(width: 15),
            if (!lanOnly && sourceIndex == 0) ...[
              const Expanded(
                flex: 2,
                child: _FilterDropdown(),
              ),
              const SizedBox(width: 15),
              const _OnlinePagination(),
            ] else ...[
              const Expanded(
                child: _LanControls(),
              ),
              const SizedBox(width: 15),
              const _LanPagination(),
            ],
          ],
        ),
      ),
    );
  }
}

class _OnlinePagination extends StatelessWidget {
  const _OnlinePagination();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: BlocBuilder<ServerListCubit, ServerListState>(
        builder: (context, state) {
          final pageText = '${state.page ?? 0}/${state.pages ?? 0}';

          return KyberTabBar(
            selectedIndex: -1,
            onChanged: (value) {
              if (value == 0) {
                context.read<ServerListCubit>().previousPage();
              } else if (value == 2) {
                context.read<ServerListCubit>().nextPage();
              }
            },
            tabs: [
              const Icon(mt.Icons.arrow_back_ios_new_rounded),
              Text(pageText),
              const Icon(mt.Icons.arrow_forward_ios_rounded),
            ],
          );
        },
      ),
    );
  }
}

class _LanPagination extends StatelessWidget {
  const _LanPagination();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: BlocBuilder<LanServerListCubit, ServerListState>(
        builder: (context, state) {
          final pageText = '${state.page ?? 0}/${state.pages ?? 0}';

          return KyberTabBar(
            selectedIndex: -1,
            onChanged: (value) {
              if (value == 0) {
                context.read<LanServerListCubit>().previousPage();
              } else if (value == 2) {
                context.read<LanServerListCubit>().nextPage();
              }
            },
            tabs: [
              const Icon(mt.Icons.arrow_back_ios_new_rounded),
              Text(pageText),
              const Icon(mt.Icons.arrow_forward_ios_rounded),
            ],
          );
        },
      ),
    );
  }
}

class _LanControls extends StatelessWidget {
  const _LanControls();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: KyberInput(
            placeholder: l10n.text('serverBrowser.searchLanPlaceholder'),
            onChanged: context.read<LanServerListCubit>().setQuery,
          ),
        ),
        const SizedBox(width: 10),
        KyberButton(
          text: l10n.text('common.refresh'),
          onPressed: () => context.read<LanServerListCubit>().loadServers(),
        ),
        const SizedBox(width: 10),
        KyberButton(
          text: l10n.text('serverBrowser.directConnect'),
          onPressed: () async {
            final result = await showKyberDialog<LanDirectConnectResult?>(
              context: context,
              builder: (_) => const LanDirectConnectDialog(),
            );
            if (!context.mounted) {
              return;
            }
            if (result == null) {
              return;
            }

            try {
              final server = await LanServerHelper.directConnect(
                address: result.host,
                port: result.port,
              );
              if (!context.mounted) {
                return;
              }

              context.read<ServerBrowserCubit>().selectServer(server);
              context.read<ServerBrowserCubit>().joinServer();
            } on Object catch (error) {
              NotificationService.error(
                title: l10n.text('serverBrowser.directConnectFailed'),
                message: error.toString(),
              );
            }
          },
        ),
        const SizedBox(width: 10),
        BlocBuilder<LanServerListCubit, ServerListState>(
          builder: (context, state) {
            final loaded = state is ServerListLoaded ? state.servers.length : 0;
            return Text(
              l10n.text(
                'serverBrowser.lanCount',
                params: {'count': loaded},
              ),
              style: const TextStyle(fontFamily: FontFamily.battlefrontUI),
            );
          },
        ),
      ],
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KyberSearchFilterDropdown(
      onSearchChanged: (value) {
        final filter = context.read<ServerListCubit>().filter;

        context.read<ServerListCubit>().setFilter(
          filter.copyWith(query: value),
        );
      },
      dropdownContent: BlocBuilder<ServerListCubit, ServerListState>(
        builder: (context, state) {
          final cubit = context.read<ServerListCubit>();
          return SuperListView(
            children: [
              KyberFilterSection<ServerRegion>(
                title: l10n.text('serverBrowser.filter.region'),
                selectedItems: [cubit.filter.region],
                items: toSelectorItems(
                  ServerRegion.values,
                  title: (e) => e.displayName,
                ),
                onChanged: (selected) {
                  cubit.setFilter(
                    cubit.filter.copyWith(region: selected.firstOrNull),
                  );
                },
              ),
              KyberFilterSection<ServerType>(
                title: l10n.text('serverBrowser.filter.serverType'),
                selectedItems: [cubit.filter.type],
                items: toSelectorItems(
                  ServerType.values,
                  title: (e) => e.name,
                ),
                onChanged: (selected) {
                  cubit.setFilter(
                    cubit.filter.copyWith(type: selected.firstOrNull),
                  );
                },
              ),
              KyberFilterSection<GameType>(
                title: l10n.text('serverBrowser.filter.gameType'),
                selectedItems: [cubit.filter.gameType],
                items: toSelectorItems(
                  GameType.values,
                  title: (e) => e.name,
                ),
                onChanged: (selected) {
                  cubit.setFilter(
                    cubit.filter.copyWith(gameType: selected.firstOrNull),
                  );
                },
              ),
              KyberFilterSection<String>(
                title: l10n.text('serverBrowser.filter.gameMode'),
                selectedItems: cubit.filter.modes,
                includeAll: true,
                items: toSelectorItems(
                  filterModes.map((e) => e.$1),
                  title: (e) => e,
                ),
                onChanged: (selected) {
                  cubit.setFilter(
                    cubit.filter.copyWith(modes: selected),
                  );
                },
                spacing: 120,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusWidget extends StatelessWidget {
  const _StatusWidget({required this.lanOnly});

  final bool lanOnly;

  @override
  Widget build(BuildContext context) {
    if (lanOnly) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    return BlocBuilder<LightswitchCubit, LightswitchStatus>(
      builder: (context, apiState) {
        if (apiState.status != KyberStatusEnum.warning) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const .only(bottom: 20),
          child: KyberCard(
            padding: .zero,
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                SizedBox(
                  height: 45,
                  child: Padding(
                    padding: const .symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: .start,
                      mainAxisAlignment: .center,
                      children: [
                        Text(
                          l10n.text('common.warning'),
                          style: .new(
                            fontFamily: FontFamily.battlefrontUI,
                            fontSize: 21,
                            color: kDefaultActiveColor,
                            shadows: [
                              Shadow(
                                color: kDefaultActiveColor.withValues(
                                  alpha: 0.55,
                                ),
                                offset: const Offset(0, 1),
                                blurRadius: 20,
                              ),
                            ],
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const CardSection(),
                Padding(
                  padding: const .symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          apiState.message ??
                              l10n.text('serverBrowser.warningUnavailable'),
                          style: const TextStyle(
                            fontFamily: FontFamily.battlefrontUI,
                            fontSize: 15,
                            height: 1,
                          ),
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
