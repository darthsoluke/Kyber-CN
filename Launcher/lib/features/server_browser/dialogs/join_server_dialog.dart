import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as mt;
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/core.dart';
import 'package:kyber_launcher/features/kyber/services/map_helper.dart';
import 'package:kyber_launcher/features/mod_collections/providers/mod_collection_cubit.dart';
import 'package:kyber_launcher/features/mods/widgets/collection_list/collection_icon.dart';
import 'package:kyber_launcher/features/server_browser/helpers/lan_server_helper.dart';
import 'package:kyber_launcher/features/server_browser/models/server_filter.dart';
import 'package:kyber_launcher/features/server_browser/services/join_server_preflight_service.dart';
import 'package:kyber_launcher/gen/assets.gen.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/main.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/buttons/normal_button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';
import 'package:kyber_launcher/shared/ui/elements/dropdown/kyber_dropdown.dart';
import 'package:kyber_launcher/shared/ui/elements/kyber_input.dart';
import 'package:kyber_launcher/shared/ui/elements/kyber_tab_bar.dart';
import 'package:kyber_launcher/shared/ui/utils/button_builder.dart';
import 'package:logging/logging.dart';

class CosmeticModsDialog extends StatefulWidget {
  const CosmeticModsDialog({
    required this.server,
    this.skipPasswordCheck = false,
    super.key,
  });

  final Object server;
  final bool skipPasswordCheck;

  @override
  State<CosmeticModsDialog> createState() => _CosmeticModsDialogState();
}

class _CosmeticModsDialogState extends State<CosmeticModsDialog> {
  static final _logger = Logger('join_server_dialog');
  final _preflight = JoinServerPreflightService();

  late bool correctPassword;

  String password = '';
  bool withoutMods = true;
  bool spectator = false;
  bool showInstanceSelector = false;

  late Server serverInfo;

  List<ModCollectionMetaData> collections = [];
  ModCollectionMetaData? selectedCollection;

  @override
  void initState() {
    serverInfo = widget.server is ServerGroup
        ? (widget.server as ServerGroup).getPreferredServer()
        : widget.server as Server;
    correctPassword = widget.skipPasswordCheck || !serverInfo.requiresPassword;
    withoutMods = !Preferences.general.useCosmetics;
    _logger.info(
      'LAN_STAGE[join_dialog.init] '
      'id=${serverInfo.id} isLan=${LanServerHelper.isLanServer(serverInfo)} '
      'apiBackedJoin=${LanServerHelper.hasApiBackedJoin(serverInfo)} '
      'requiresPassword=${serverInfo.requiresPassword} '
      'skipPasswordCheck=${widget.skipPasswordCheck}',
    );
    final mods = serverInfo.mods
        .map(
          (e) => CollectionMod(name: e.name, version: e.version, link: e.link),
        )
        .toList();
    for (final collection in collectionBox.values) {
      final gameplayMods = collection
          .getLocalMods(
            onlyGameplay: true,
            expandCollections: true,
            expandGameplayCollections: false,
          )
          .whereType<FrostyMod>()
          .map((e) => e.toCollectionMod())
          .toList();

      if (const ListEquality<CollectionMod>().equals(gameplayMods, mods) ||
          collection.isCosmetic ||
          gameplayMods.isEmpty) {
        collections.add(collection);
      }
    }

    if (Preferences.general.selectedCosmeticCollection != null) {
      final selectedCollectionId =
          Preferences.general.selectedCosmeticCollection;
      if (collectionBox.containsKey(selectedCollectionId) &&
          collections.any((x) => x.localId == selectedCollectionId)) {
        selectedCollection = collectionBox.get(selectedCollectionId);
      }
    }

    selectedCollection ??= collections.firstOrNull;

    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> checkPassword() async {
    try {
      final result = await _preflight.checkPassword(
        server: serverInfo,
        password: password,
      );
      if (!mounted) {
        return;
      }

      if (result.allowed) {
        setState(() {
          correctPassword = true;
        });
        return;
      }

      NotificationService.showNotification(
        message:
            result.message ??
            context.l10n.text(result.messageKey ?? 'join.genericError'),
        severity: InfoBarSeverity.error,
      );
    } on Object catch (e, s) {
      _logger.severe(
        'LAN_STAGE[join_dialog.password_check.api.error] '
        'id=${serverInfo.id} error=$e',
        e,
        s,
      );
      if (!mounted) {
        return;
      }
      if (e is GrpcError && e.code == StatusCode.notFound) {
        Navigator.pop(context);
        NotificationService.showNotification(
          message: context.l10n.text('join.serverNotFound'),
          severity: InfoBarSeverity.error,
        );
      } else {
        Logger.root.severe('An error occurred', e, s);
        NotificationService.showNotification(
          message: context.l10n.text('join.genericError'),
          severity: InfoBarSeverity.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KyberContentDialog(
      title: Text(context.l10n.text('join.title')),
      constraints: const BoxConstraints(
        maxHeight: 500,
        maxWidth: 700,
      ),
      content: SizedBox(
        width: 450,
        child: Builder(
          builder: (context) {
            if (!correctPassword) {
              return Column(
                children: [
                  Text(
                    context.l10n.text('join.requiresPassword'),
                    style: const TextStyle(
                      color: kWhiteColor,
                    ),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  Align(child: Text(context.l10n.text('join.enterPassword'))),
                  const SizedBox(
                    height: 2.5,
                  ),
                  KyberInput(
                    onFieldSubmitted: (value) => checkPassword(),
                    placeholder: context.l10n.text('common.password'),
                    isSensitive: true,
                    onChanged: (value) {
                      setState(() {
                        password = value;
                      });
                    },
                  ),
                ],
              );
            }

            return Column(
              children: [
                if (widget.server is ServerGroup) ...[
                  RichText(
                    text: TextSpan(
                      text: context.l10n.text('join.joiningInstance'),
                      style: const TextStyle(
                        fontSize: 16,
                        color: kWhiteColor,
                        fontFamily: FontFamily.battlefrontUI,
                      ),
                      children: [
                        TextSpan(
                          text:
                              '#${(widget.server as ServerGroup).getInstanceId(
                                serverInfo.id,
                              )}',
                          style: TextStyle(
                            color: kActiveColor,
                          ),
                        ),
                        const TextSpan(
                          text: ' | ',
                          style: TextStyle(
                            color: decoColor,
                          ),
                        ),
                        TextSpan(
                          text:
                              '(${serverInfo.playerCount}/${serverInfo.maxPlayerCount})',
                        ),
                      ],
                    ),
                  ),
                  if (!showInstanceSelector) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: ButtonBuilder(
                        onClick: () =>
                            setState(() => showInstanceSelector = true),
                        builder: (context, hovered) {
                          return Text(
                            context.l10n.text('join.changeInstance'),
                            style: TextStyle(
                              color: hovered ? kActiveColor : kWhiteColor,
                              fontFamily: FontFamily.battlefrontUI,
                              decoration: TextDecoration.underline,
                            ),
                          );
                        },
                      ),
                    ),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: KyberDropdown<Server>(
                        onChanged: (value) {
                          setState(() => serverInfo = value);
                        },
                        itemBuilder: (item) {
                          final instanceId = (widget.server as ServerGroup)
                              .getInstanceId(item.value.id);
                          final serverInfo = item.value;
                          final modeName =
                              serverInfo.levelSetup.modeName.isNotEmpty
                              ? serverInfo.levelSetup.modeName
                              : MapHelper.getMode(
                                      serverInfo.levelSetup.mode,
                                    )?.name ??
                                    context.l10n.text('join.unknownMode');
                          final mapName =
                              serverInfo.levelSetup.mapName.isNotEmpty
                              ? serverInfo.levelSetup.mapName
                              : MapHelper.getMap(
                                      serverInfo.levelSetup.mode,
                                      serverInfo.levelSetup.map,
                                    )?.name ??
                                    context.l10n.text('join.unknownMap');
                          return Row(
                            children: [
                              SizedBox(
                                width: 70,
                                height: 45,
                                child: Builder(
                                  builder: (context) {
                                    if (serverInfo.mapImageHash.isNotEmpty) {
                                      return CachedNetworkImage(
                                        imageUrl: sl
                                            .get<KyberGRPCService>()
                                            .imageUrl(serverInfo.mapImageHash),
                                        fit: BoxFit.cover,
                                        alignment: Alignment.centerLeft,
                                        colorBlendMode: BlendMode.darken,
                                        color: Colors.black.withValues(
                                          alpha: .12,
                                        ),
                                      );
                                    }

                                    return MapHelper.getImageForMap(
                                      serverInfo.levelSetup.map,
                                    )!.image(
                                      fit: BoxFit.cover,
                                      alignment: Alignment.centerLeft,
                                      colorBlendMode: BlendMode.darken,
                                      color: Colors.black.withValues(
                                        alpha: .12,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Container(width: 2, height: 45, color: decoColor),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ).copyWith(top: 5),
                                      child: Text(
                                        context.l10n.text(
                                          'join.instance',
                                          params: {'id': instanceId},
                                        ),
                                        style: const TextStyle(
                                          fontFamily: FontFamily.battlefrontUI,
                                          fontSize: 16,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          RichText(
                                            text: TextSpan(
                                              style: const TextStyle(
                                                fontSize: 16,
                                                color: kWhiteColor1,
                                                fontFamily:
                                                    FontFamily.battlefrontUI,
                                              ),
                                              children: [
                                                TextSpan(
                                                  text: modeName,
                                                ),
                                                const TextSpan(
                                                  text: ' | ',
                                                  style: TextStyle(
                                                    color: decoColor,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: mapName,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: Text(
                                  '${item.value.playerCount}/${item.value.maxPlayerCount}',
                                  style: const TextStyle(
                                    fontFamily: FontFamily.battlefrontUI,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                        items: (widget.server as ServerGroup).getSorted().map((
                          e,
                        ) {
                          return DropdownItem(
                            value: e,
                            label: context.l10n.text(
                              'join.instance',
                              params: {
                                'id': (widget.server as ServerGroup)
                                    .getInstanceId(e.id),
                              },
                            ),
                          );
                        }).toList(),
                        selectedItem: serverInfo,
                      ),
                    ),
                  ],
                  const SizedBox(height: 15),
                ],
                Text(context.l10n.text('join.cosmeticsTitle')),
                Text(
                  context.l10n.text('join.cosmeticsDescription'),
                  style: const TextStyle(
                    color: kWhiteColor,
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                SizedBox(
                  height: 35,
                  child: KyberTabBar(
                    tabs: [
                      Text(context.l10n.text('join.withCosmetics')),
                      Text(context.l10n.text('join.withoutCosmetics')),
                    ],
                    selectedIndex: withoutMods ? 1 : 0,
                    onChanged: (index) {
                      Preferences.general.useCosmetics = index == 0;
                      setState(() {
                        withoutMods = index == 1;
                      });
                    },
                  ),
                ),
                if (!withoutMods) ...[
                  const SizedBox(
                    height: 30,
                  ),
                  KyberDropdown<ModCollectionMetaData>(
                    onChanged: (value) {
                      setState(() => selectedCollection = value);
                      Preferences.general.selectedCosmeticCollection =
                          value.localId;
                    },
                    itemBuilder: (item) {
                      return Row(
                        children: [
                          SizedBox(
                            height: 40,
                            width: 40,
                            child: CollectionIcon(collection: item.value),
                          ),
                          Container(width: 2, height: 40, color: decoColor),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(
                                item.value.title,
                                style: const TextStyle(
                                  fontFamily: FontFamily.battlefrontUI,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                    items: collections
                        .map((e) => DropdownItem(value: e, label: e.title))
                        .toList(),
                    selectedItem: selectedCollection,
                    placeholder: context.l10n.text('join.selectCollection'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        KyberButton(
          text: context.l10n.text('common.cancel'),
          onPressed: Navigator.of(context).pop,
        ),
        if (!correctPassword)
          KyberButton(
            text: context.l10n.text('common.next'),
            onPressed: checkPassword,
          ),
        if (correctPassword)
          NormalButton(
            onPressed: () => setState(() => spectator = !spectator),
            iconData: spectator
                ? mt.Icons.check_circle
                : mt.Icons.circle_outlined,
            label: Row(
              children: [
                const Icon(mt.Icons.remove_red_eye_outlined),
                const SizedBox(width: 6),
                Text(context.l10n.text('common.spectate')),
              ],
            ),
          ),
        if (correctPassword)
          KyberButton(
            text: context.l10n.text('common.joinServer'),
            icon: Assets.icons.kyberLogo.svg(height: 20),
            onPressed: () async {
              try {
                final preflight = await _preflight.validateSubmit(
                  server: serverInfo,
                  password: password,
                );
                if (!context.mounted) {
                  return;
                }
                if (!preflight.allowed) {
                  NotificationService.showNotification(
                    message:
                        preflight.message ??
                        context.l10n.text(
                          preflight.messageKey ?? 'join.genericError',
                        ),
                    severity: InfoBarSeverity.error,
                  );
                  return;
                }
              } on Object catch (e, s) {
                _logger.severe(
                  'LAN_STAGE[join_dialog.submit.api.error] '
                  'id=${serverInfo.id} error=$e',
                  e,
                  s,
                );
                if (!context.mounted) {
                  return;
                }
                if (e is GrpcError && e.code == StatusCode.permissionDenied) {
                  Logger.root.severe('An error occurred', e, s);
                  Navigator.pop(context);
                  NotificationService.showNotification(
                    message:
                        e.message ?? context.l10n.text('join.bannedFromServer'),
                    severity: InfoBarSeverity.error,
                  );
                } else {
                  Logger.root.severe('An error occurred', e, s);
                  NotificationService.showNotification(
                    message: e is GrpcError
                        ? e.message ?? e.code.toString()
                        : context.l10n.text('join.genericError'),
                    severity: InfoBarSeverity.error,
                  );
                }
                return;
              }

              final result = JoinDialogResult(
                collection: withoutMods
                    ? ModCollectionMetaData.noMods()
                    : selectedCollection ?? ModCollectionMetaData.noMods(),
                spectator: spectator,
                password: password,
                instanceId: widget.server is ServerGroup
                    ? serverInfo.meta['instance_id']
                    : null,
              );
              _logger.info(
                'LAN_STAGE[join_dialog.submit.accepted] '
                'id=${serverInfo.id} spectator=$spectator '
                'withoutMods=$withoutMods '
                'instanceId=${result.instanceId ?? ''}',
              );

              if (!context.mounted) {
                return;
              }
              Navigator.of(context).pop(result);
            },
          ),
      ],
    );
  }
}

class JoinDialogResult {
  JoinDialogResult({
    required this.collection,
    required this.spectator,
    this.password = '',
    this.instanceId,
  });

  final ModCollectionMetaData collection;
  final bool spectator;
  final String password;

  /// Only useful for server groups
  final String? instanceId;
}
