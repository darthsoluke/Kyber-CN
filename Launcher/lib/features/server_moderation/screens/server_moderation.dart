import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as mt;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart';
import 'package:intl/intl.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/kyber/helper/kyber_server_helper.dart';
import 'package:kyber_launcher/features/maxima/providers/maxima_cubit.dart';
import 'package:kyber_launcher/features/mod_browser/screens/mod_details.dart';
import 'package:kyber_launcher/features/server_browser/dialogs/join_server_dialog.dart';
import 'package:kyber_launcher/features/server_browser/widgets/server_list/server_list_header.dart';
import 'package:kyber_launcher/features/server_moderation/dialogs/moderation_ban_dialog.dart';
import 'package:kyber_launcher/features/server_moderation/dialogs/moderation_input_dialog.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_cubit.dart';
import 'package:kyber_launcher/gen/assets.gen.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';
import 'package:logging/logging.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:tinycolor2/tinycolor2.dart';

class ServerModeration extends StatefulWidget {
  const ServerModeration({required this.selectedPage, super.key});

  final int selectedPage;

  @override
  State<ServerModeration> createState() => _ServerModerationState();
}

class _ServerModerationState extends State<ServerModeration> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<ModerationCubit, ModerationServerState>(
      builder: (context, state) {
        if (state.id == null) {
          return const Placeholder();
        }

        if (widget.selectedPage == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KyberHeader(
                sections: [
                  FixedWidthHeaderSection(
                    width: 131,
                    children: [
                      const SizedBox(width: 10),
                      Text(l10n.text('common.options')),
                    ],
                  ),
                  ExpandedHeaderSection(
                    children: [
                      Text(
                        state.localControl
                            ? 'LOCAL CONTROL'
                            : l10n.text('moderation.moderators'),
                      ),
                    ],
                  ),
                  ExpandedHeaderSection(
                    children: [
                      Text(
                        state.localControl
                            ? 'LOCAL BLACKLIST'
                            : l10n.text('moderation.bannedPlayers'),
                      ),
                    ],
                  ),
                ],
              ),
              const ContainerSeparator(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 130,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              spacing: 15,
                              children: [
                                KyberButton(
                                  text: l10n.text('common.play'),
                                  onPressed: () async {
                                    if (state.server == null) return;

                                    final result =
                                        await showKyberDialog<
                                          JoinDialogResult?
                                        >(
                                          context: context,
                                          builder: (_) => CosmeticModsDialog(
                                            server: state.server!,
                                            skipPasswordCheck: true,
                                          ),
                                        );

                                    if (result == null) {
                                      return;
                                    }

                                    final server = state.server!;
                                    await KyberServerHelper.joinServer(
                                      server,
                                      selectedCollection: result.collection,
                                      spectator: result.spectator,
                                      password: result.password,
                                    );
                                  },
                                ),
                                KyberButton(
                                  text: l10n.text('common.spectate'),
                                  onPressed: () {
                                    unawaited(
                                      KyberServerHelper.joinServer(
                                        state.server!,
                                        spectator: true,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const CardSection(),
                          Padding(
                            padding: const .all(10),
                            child: Column(
                              children: [
                                KyberButton(
                                  text: l10n.text('common.copy'),
                                  onPressed: () {
                                    final service = sl.get<KyberGRPCService>();
                                    final target =
                                        'join_server?server_id='
                                        '${state.server?.id}';
                                    final uri = Uri(
                                      scheme: service.httpScheme,
                                      host: service.httpHostname,
                                      path: 'redirect',
                                      queryParameters: {
                                        'target': target,
                                      },
                                    );
                                    unawaited(
                                      Clipboard.setData(
                                        ClipboardData(text: uri.toString()),
                                      ),
                                    );
                                    NotificationService.info(
                                      message: l10n.text(
                                        'common.copiedToClipboard',
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const CardSection(),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              spacing: 15,
                              children: [
                                if (state.localControl) ...[
                                  NormalButton(
                                    label: const Text('REFRESH STATE'),
                                    onPressed: () {
                                      unawaited(
                                        context
                                            .read<ModerationCubit>()
                                            .refreshLocalState(),
                                      );
                                    },
                                  ),
                                  NormalButton(
                                    label: const Text('CLEAR BLACKLIST'),
                                    onPressed: () {
                                      unawaited(
                                        context
                                            .read<ModerationCubit>()
                                            .clearLocalBlacklist(),
                                      );
                                    },
                                  ),
                                  NormalButton(
                                    label: Text(
                                      l10n.text('moderation.kickAll'),
                                    ),
                                    onPressed: () async {
                                      final reason =
                                          await showKyberDialog<String?>(
                                            context: context,
                                            builder: (_) =>
                                                const ModerationInputDialog(
                                                  title: 'Kick All',
                                                  prompt:
                                                      'Reason sent to every '
                                                      'player:',
                                                ),
                                          );
                                      if (reason == null || !context.mounted) {
                                        return;
                                      }

                                      await context
                                          .read<ModerationCubit>()
                                          .kickAllPlayers(reason: reason);
                                    },
                                  ),
                                  NormalButton(
                                    label: Text(
                                      l10n.text('moderation.banAll'),
                                      textAlign: TextAlign.center,
                                    ),
                                    onPressed: () async {
                                      final reason =
                                          await showKyberDialog<String?>(
                                            context: context,
                                            builder: (_) =>
                                                const ModerationInputDialog(
                                                  title: 'Ban All',
                                                  prompt: 'Blacklist reason:',
                                                ),
                                          );
                                      if (reason == null || !context.mounted) {
                                        return;
                                      }

                                      await context
                                          .read<ModerationCubit>()
                                          .banAllPlayers(reason: reason);
                                    },
                                  ),
                                ] else ...[
                                  NormalButton(
                                    label: Text(
                                      l10n.text('moderation.exportBans'),
                                    ),
                                    onPressed:
                                        NotificationService.notImplemented,
                                  ),
                                  NormalButton(
                                    label: Text(
                                      l10n.text('moderation.importBans'),
                                    ),
                                    onPressed:
                                        NotificationService.notImplemented,
                                  ),
                                  NormalButton(
                                    label: Text(
                                      l10n.text('moderation.kickAll'),
                                    ),
                                    onPressed:
                                        NotificationService.notImplemented,
                                  ),
                                  NormalButton(
                                    label: Text(
                                      l10n.text('moderation.banAll'),
                                      textAlign: TextAlign.center,
                                    ),
                                    onPressed:
                                        NotificationService.notImplemented,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const ContainerSeparatorH(),
                    Expanded(
                      child: state.localControl
                          ? const _LocalControlInfo()
                          : const _ModeratorContainer(),
                    ),
                    const ContainerSeparatorH(),
                    Expanded(
                      child: state.localControl
                          ? const _LocalBlacklistContainer()
                          : const _PunishmentContainer(),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KyberHeader(
              sections: [
                ExpandedHeaderSection(
                  children: [Text(l10n.text('moderation.eventLog'))],
                ),
                ExpandedHeaderSection(
                  children: [Text(l10n.text('moderation.lightSide'))],
                ),
                ExpandedHeaderSection(
                  children: [Text(l10n.text('moderation.darkSide'))],
                ),
              ],
            ),
            const ContainerSeparator(),
            const Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _Console()),
                  ContainerSeparatorH(),
                  Expanded(child: _TeamContainer(teamId: 1)),
                  ContainerSeparatorH(),
                  Expanded(child: _TeamContainer(teamId: 2)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UserManager extends StatefulWidget {
  const _UserManager();

  @override
  State<_UserManager> createState() => _UserManagerState();
}

class _UserManagerState extends State<_UserManager> {
  @override
  Widget build(BuildContext context) {
    return KyberEventContainer(
      child: Text(
        'User Manager'.toUpperCase(),
        style: const TextStyle(
          fontFamily: FontFamily.battlefrontUI,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _Console extends StatefulWidget {
  const _Console();

  @override
  State<_Console> createState() => _ConsoleState();
}

class _ConsoleState extends State<_Console> {
  final controller = TextEditingController();
  final FocusNode focusNode = FocusNode();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: BlocBuilder<ModerationCubit, ModerationServerState>(
            builder: (context, state) {
              return SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: state.commands.map((item) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text.rich(
                          formatText(item),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(15),
          child: mt.TextFormField(
            controller: controller,
            style: const TextStyle(
              color: kWhiteColor,
              fontFamily: FontFamily.battlefrontUI,
              height: 1.5,
            ),
            maxLines: 4,
            minLines: 1,
            decoration: const mt.InputDecoration(
              hintText: '/COMMAND OR SEND MESSAGE',
              hintStyle: TextStyle(
                fontSize: 14,
                height: 1,
                color: kWhiteColor,
                fontFamily: FontFamily.battlefrontUI,
              ),
              isDense: true,
              enabledBorder: mt.OutlineInputBorder(
                borderSide: BorderSide(color: kGrayColor, width: 2),
                borderRadius: BorderRadius.all(
                  Radius.circular(kDefaultInnerBorderRadius),
                ),
              ),
              focusedBorder: mt.OutlineInputBorder(
                borderSide: BorderSide(color: kWhiteColor, width: 2),
                borderRadius: BorderRadius.all(
                  Radius.circular(kDefaultInnerBorderRadius),
                ),
              ),
            ),
            focusNode: focusNode,
            textInputAction: TextInputAction.send,
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  required maxLength,
                }) => null,
            maxLength: controller.text.startsWith('/') ? null : 127,
            onChanged: (value) {
              setState(() {});
            },
            onFieldSubmitted: (value) {
              if (value.isEmpty) {
                return;
              }

              context.read<ModerationCubit>().sendCommand(value);
              controller.clear();
              focusNode.requestFocus();
            },
          ),
        ),
      ],
    );
  }

  TextSpan formatText(String text) {
    final spans = <TextSpan>[];

    final boldRegex = RegExp(r'\*\*(.*?)\*\*');
    final strikeThroughRegex = RegExp('~~(.*?)~~');

    final boldMatches = boldRegex.allMatches(text);
    final strikeMatches = strikeThroughRegex.allMatches(text);
    var currentIndex = 0;

    const defaultStyle = TextStyle(
      fontFamily: FontFamily.iBMPlexMono,
      fontSize: 12,
    );

    while (currentIndex < text.length) {
      final boldMatch = boldMatches.isNotEmpty ? boldMatches.first : null;
      final strikeMatch = strikeMatches.isNotEmpty ? strikeMatches.first : null;

      if (boldMatch != null && boldMatch.start == currentIndex) {
        spans.add(
          TextSpan(
            text: boldMatch.group(1),
            style: defaultStyle.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        );
        currentIndex = boldMatch.end;
      } else if (strikeMatch != null && strikeMatch.start == currentIndex) {
        spans.add(
          TextSpan(
            text: strikeMatch.group(1),
            style: defaultStyle.copyWith(
              decoration: TextDecoration.lineThrough,
            ),
          ),
        );
        currentIndex = strikeMatch.end;
      } else {
        spans.add(
          TextSpan(
            text: text[currentIndex],
            style: defaultStyle,
          ),
        );
        currentIndex++;
      }
    }

    return TextSpan(
      children: spans,
    );
  }
}

class _ModeratorContainer extends StatefulWidget {
  const _ModeratorContainer();

  @override
  State<_ModeratorContainer> createState() => _ModeratorContainerState();
}

class _PunishmentContainer extends StatefulWidget {
  const _PunishmentContainer();

  @override
  State<_PunishmentContainer> createState() => _PunishmentContainerState();
}

class _PunishmentContainerState extends State<_PunishmentContainer> {
  int? expanded;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ModerationCubit, ModerationServerState>(
      builder: (context, state) {
        final punishments = state.punishments;
        return SuperListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          itemBuilder: (context, index) {
            final punishment = punishments.elementAt(index);
            return _Punishment(
              expanded: index == expanded,
              isEven: index.isEven,
              onTap: () {
                if (index == expanded) {
                  expanded = null;
                } else {
                  expanded = index;
                }

                setState(() {});
              },
              punishment: punishment,
            );
          },
          separatorBuilder: (context, index) {
            return const Divider();
          },
          itemCount: punishments.length,
        );
      },
    );
  }
}

class _LocalControlInfo extends StatelessWidget {
  const _LocalControlInfo();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ModerationCubit, ModerationServerState>(
      builder: (context, state) {
        return KyberEventContainer(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: kWhiteColor,
                fontFamily: FontFamily.iBMPlexMono,
                fontSize: 13,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  Text(
                    'LOCAL DEDICATED SERVER'.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: FontFamily.battlefrontUI,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  Text('Server: ${state.server?.name ?? '-'}'),
                  Text(
                    'Players: ${state.players.length}/'
                    '${state.server?.maxPlayerCount ?? 0}',
                  ),
                  Text('Blacklist: ${state.localBlacklistEntries.length}'),
                  const SizedBox(height: 10),
                  const Text(
                    'Available local controls:',
                  ),
                  const Text('- Kick / ban / swap players from live teams'),
                  const Text('- Broadcast admin messages from console'),
                  const Text('- Shuffle or swap all teams'),
                  const Text('- Change map, restart, pause timer'),
                  const Text('- Adjust bot counts in host settings'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LocalBlacklistContainer extends StatelessWidget {
  const _LocalBlacklistContainer();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ModerationCubit, ModerationServerState>(
      builder: (context, state) {
        final entries = state.localBlacklistEntries;
        if (entries.isEmpty) {
          return const Center(
            child: Text(
              'No local blacklist entries',
              style: TextStyle(
                fontFamily: FontFamily.battlefrontUI,
                fontSize: 18,
              ),
            ),
          );
        }

        return SuperListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          itemBuilder: (context, index) {
            final entry = entries.elementAt(index);
            final expires = entry.expiresAt == null
                ? 'PERMANENT'
                : DateFormat.yMd().add_Hm().format(entry.expiresAt!);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: index.isEven
                    ? const Color(0xFFD9D9D9).withValues(alpha: .1)
                    : const Color(0xFFD9D9D9).withValues(alpha: .2),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.name} (${entry.id})',
                    style: const TextStyle(
                      fontFamily: FontFamily.battlefrontUI,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'UNTIL: $expires',
                    style: const TextStyle(
                      fontFamily: FontFamily.iBMPlexMono,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'REASON: ${entry.reason}',
                    style: const TextStyle(
                      fontFamily: FontFamily.iBMPlexMono,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  KyberButton(
                    text: 'UNBAN',
                    onPressed: () {
                      unawaited(
                        context.read<ModerationCubit>().unbanPlayer(entry.id),
                      );
                    },
                  ),
                ],
              ),
            );
          },
          separatorBuilder: (context, index) => const Divider(),
          itemCount: entries.length,
        );
      },
    );
  }
}

class _Punishment extends StatelessWidget {
  const _Punishment({
    required this.expanded,
    required this.isEven,
    required this.onTap,
    required this.punishment,
  });

  final bool expanded;
  final bool isEven;
  final VoidCallback onTap;
  final Punishment punishment;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ButtonBuilder(
          onClick: onTap,
          builder: (context, hovered) {
            return AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: TextStyle(
                color: hovered ? Colors.black : Colors.white,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: hovered
                      ? const Color(0xFFD9D9D9)
                      : isEven
                      ? const Color(0xFFD9D9D9).withValues(alpha: .1)
                      : const Color(0xFFD9D9D9).withValues(alpha: .2),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${punishment.user.name} (${punishment.user.id})',
                      style: const TextStyle(
                        fontFamily: FontFamily.battlefrontUI,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        if (expanded)
          Stack(
            children: [
              Positioned.fill(
                right: null,
                left: 2,
                child: SizedBox(
                  width: 2,
                  child: CustomPaint(
                    foregroundPainter: DashedLineVerticalPainter(),
                    willChange: true,
                  ),
                ),
              ),
              Positioned.fill(
                left: null,
                child: SizedBox(
                  width: 2,
                  child: CustomPaint(
                    foregroundPainter: DashedLineVerticalPainter(),
                    willChange: true,
                  ),
                ),
              ),
              Builder(
                builder: (context) {
                  final until = DateTime.fromMillisecondsSinceEpoch(
                    punishment.expiresAt.toInt(),
                  );
                  final isPermanent = punishment.expiresAt == 0;
                  final expires = isPermanent
                      ? 'PERMANENT'
                      : DateFormat.yMd().format(until);
                  final remainingDuration = formatDuration(
                    until.difference(DateTime.now()),
                  );
                  final remaining = isPermanent ? '' : ' ($remainingDuration)';
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'UNTIL: $expires$remaining',
                          style: const TextStyle(
                            fontFamily: FontFamily.iBMPlexMono,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'REASON: ${punishment.reason}',
                          style: const TextStyle(
                            fontFamily: FontFamily.iBMPlexMono,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: 10,
                            children: [
                              KyberButton(
                                text: 'UNBAN',
                                onPressed: () {
                                  unawaited(
                                    context.read<ModerationCubit>().unbanPlayer(
                                      punishment.user.id,
                                    ),
                                  );
                                  NotificationService.info(
                                    message: 'Player unbanned',
                                  );
                                },
                              ),
                              const KyberButton(
                                text: 'MODIFY',
                                onPressed: NotificationService.notImplemented,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  );
                },
              ),
              CustomPaint(
                painter: DashedLineVerticalPainter(),
              ),
            ],
          ),
      ],
    );
  }

  String formatDuration(Duration duration) {
    if (duration.isNegative) {
      return 'Time has elapsed';
    }

    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final parts = <String>[];

    if (days > 0) {
      parts.add("$days day${days != 1 ? 's' : ''}");
    }

    if (hours > 0 && days < 1) {
      parts.add("$hours hour${hours != 1 ? 's' : ''}");
    }

    if (minutes > 0 && days < 1 && hours < 1) {
      parts.add("$minutes minute${minutes != 1 ? 's' : ''}");
    }

    if (seconds > 0 && days < 1 && hours < 1 && minutes < 1) {
      parts.add("$seconds second${seconds != 1 ? 's' : ''}");
    }

    return '${parts.join(", ")} remaining';
  }
}

class _ModeratorContainerState extends State<_ModeratorContainer> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ModerationCubit, ModerationServerState>(
      builder: (context, state) {
        final moderators = state.moderators;
        return SuperListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          itemBuilder: (context, index) {
            final player = moderators.elementAt(index);
            return HoverBuilder(
              builder: (context, hovered) {
                return AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 150),
                  style: TextStyle(
                    color: hovered ? Colors.black : Colors.white,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: hovered
                          ? const Color(0xFFD9D9D9)
                          : index.isEven
                          ? const Color(0xFFD9D9D9).withValues(alpha: .1)
                          : const Color(0xFFD9D9D9).withValues(alpha: .2),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          player.name,
                          style: const TextStyle(
                            fontFamily: FontFamily.battlefrontUI,
                            fontSize: 18,
                          ),
                        ),
                        Row(
                          children: [
                            AnimatedOpacity(
                              opacity: hovered ? 1 : 0,
                              duration: const Duration(milliseconds: 100),
                              curve: Curves.easeOut,
                              child: Row(
                                children: [
                                  _moderatorWidget(state, hovered, player),
                                ],
                              ),
                            ),
                            if (state.isModerator(player.id)) ...[
                              _moderatorWidget(state, hovered, player),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          separatorBuilder: (context, index) {
            return const Divider();
          },
          itemCount: moderators.length,
        );
      },
    );
  }

  Widget _moderatorWidget(
    ModerationServerState state,
    bool hovered,
    KyberPlayer player,
  ) => KyberTooltip(
    message: 'Promote User'.toUpperCase(),
    child: CustomSvgButton(
      hoverColor: Colors.black,
      onPressed: () async {
        if (state.isModerator(player.id)) {
          await context.read<ModerationCubit>().demotePlayer(player.id).onError(
            (error, stackTrace) {
              if (error is GrpcError) {
                NotificationService.showNotification(
                  message: error.message!,
                  severity: InfoBarSeverity.error,
                );
              } else {
                NotificationService.showNotification(
                  message: 'An error occurred',
                  severity: InfoBarSeverity.error,
                );
                Logger.root.severe('Error promoting player', error, stackTrace);
              }
            },
          );
        } else {
          await context
              .read<ModerationCubit>()
              .promotePlayer(player.id)
              .onError((error, stackTrace) {
                if (error is GrpcError) {
                  NotificationService.showNotification(
                    message: error.message!,
                    severity: InfoBarSeverity.error,
                  );
                } else {
                  NotificationService.showNotification(
                    message: 'An error occurred',
                    severity: InfoBarSeverity.error,
                  );
                  Logger.root.severe(
                    'Error demoting player',
                    error,
                    stackTrace,
                  );
                }
              });
        }
        if (!mounted) {
          return;
        }
        unawaited(context.read<ModerationCubit>().loadModerators());
      },
      color: state.isModerator(player.id)
          ? Colors.green
          : /* state.server?.creator == player.name
                  ? kActiveColor.darken(10)
                  :*/ hovered
          ? kButtonBorder
          : kActiveColor,
      path: Assets.icons.kblOpUser.path,
      size: 17,
    ),
  );
}

class _TeamContainer extends StatefulWidget {
  const _TeamContainer({required this.teamId});

  final int teamId;

  @override
  State<_TeamContainer> createState() => _TeamContainerState();
}

class _TeamContainerState extends State<_TeamContainer> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ModerationCubit, ModerationServerState>(
      builder: (context, state) {
        final players = state.players
            .where((element) => element.teamId == widget.teamId)
            .toList();
        return SuperListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          itemBuilder: (context, index) {
            final player = players.elementAt(index);
            return HoverBuilder(
              builder: (context, hovered) {
                return AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 150),
                  style: TextStyle(
                    color: hovered ? Colors.black : Colors.white,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: hovered
                          ? const Color(0xFFD9D9D9)
                          : index.isEven
                          ? const Color(0xFFD9D9D9).withValues(alpha: .1)
                          : const Color(0xFFD9D9D9).withValues(alpha: .2),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          player.name,
                          style: const TextStyle(
                            fontFamily: FontFamily.battlefrontUI,
                            fontSize: 18,
                          ),
                        ),
                        Row(
                          children: [
                            AnimatedOpacity(
                              opacity: hovered ? 1 : 0,
                              duration: const Duration(milliseconds: 100),
                              curve: Curves.easeOut,
                              child: Row(
                                children: [
                                  KyberTooltip(
                                    message: 'Swap Player'.toUpperCase(),
                                    child: CustomSvgButton(
                                      onPressed: () {
                                        context
                                            .read<ModerationCubit>()
                                            .swapTeam(player);
                                      },
                                      path: Assets.icons.kblSwap.path,
                                      hoverColor: Colors.black,
                                      color: hovered ? kButtonBorder : null,
                                      size: 17,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  KyberTooltip(
                                    message: 'Kick player'.toUpperCase(),
                                    child: CustomSvgButton(
                                      onPressed: () async {
                                        final reason =
                                            await showKyberDialog<String?>(
                                              context: context,
                                              builder: (_) =>
                                                  const ModerationInputDialog(),
                                            );
                                        if (reason == null) {
                                          return;
                                        }

                                        if (!context.mounted) {
                                          return;
                                        }
                                        await context
                                            .read<ModerationCubit>()
                                            .kickPlayer(
                                              player.id,
                                              reason: reason,
                                            )
                                            .onError((error, stackTrace) {
                                              if (error is GrpcError) {
                                                NotificationService.error(
                                                  message: error.message!,
                                                );
                                              } else {
                                                NotificationService.error(
                                                  message: 'An error occurred',
                                                );
                                                Logger.root.severe(
                                                  'Error kicking player',
                                                  error,
                                                  stackTrace,
                                                );
                                              }
                                            });
                                      },
                                      path: Assets.icons.kblKick.path,
                                      hoverColor: Colors.black,
                                      color: hovered ? kButtonBorder : null,
                                      size: 17,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  KyberTooltip(
                                    message: 'Ban player'.toUpperCase(),
                                    child: CustomSvgButton(
                                      onPressed: () async {
                                        await showKyberDialog(
                                          context: context,
                                          builder: (_) => BlocProvider.value(
                                            value: context
                                                .read<ModerationCubit>(),
                                            child: ModerationBanDialog(
                                              player: player,
                                            ),
                                          ),
                                        );
                                      },
                                      path: Assets.icons.kblBan.path,
                                      hoverColor: Colors.black,
                                      color: hovered ? kButtonBorder : null,
                                      size: 17,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  if ((!state.moderators.contains(player) &&
                                          state.server?.creatorId !=
                                              player.id) &&
                                      context
                                              .read<MaximaCubit>()
                                              .state
                                              .servicePlayer
                                              ?.id ==
                                          state.server?.creatorId)
                                    _moderatorWidget(state, hovered, player),
                                ],
                              ),
                            ),
                            if (state.moderators.contains(player) ||
                                state.server?.creatorId == player.id) ...[
                              _moderatorWidget(state, hovered, player),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          separatorBuilder: (context, index) {
            return const Divider();
          },
          itemCount: players.length,
        );
      },
    );
  }

  Widget _moderatorWidget(
    ModerationServerState state,
    bool hovered,
    ServerPlayer player,
  ) => KyberTooltip(
    message: 'Promote User'.toUpperCase(),
    child: CustomSvgButton(
      hoverColor: Colors.black,
      onPressed: () async {
        if (state.isModerator(player.id)) {
          await context.read<ModerationCubit>().demotePlayer(player.id).onError(
            (error, stackTrace) {
              if (error is GrpcError) {
                NotificationService.showNotification(
                  message: error.message!,
                  severity: InfoBarSeverity.error,
                );
              } else {
                NotificationService.showNotification(
                  message: 'An error occurred',
                  severity: InfoBarSeverity.error,
                );
                Logger.root.severe('Error promoting player', error, stackTrace);
              }
            },
          );
        } else {
          await context
              .read<ModerationCubit>()
              .promotePlayer(player.id)
              .onError((error, stackTrace) {
                if (error is GrpcError) {
                  NotificationService.showNotification(
                    message: error.message!,
                    severity: InfoBarSeverity.error,
                  );
                } else {
                  NotificationService.showNotification(
                    message: 'An error occurred',
                    severity: InfoBarSeverity.error,
                  );
                  Logger.root.severe(
                    'Error demoting player',
                    error,
                    stackTrace,
                  );
                }
              });
        }

        if (!mounted) {
          return;
        }
        unawaited(context.read<ModerationCubit>().loadModerators());
      },
      color: state.isModerator(player.id)
          ? Colors.green
          : state.server?.creatorId == player.id
          ? kActiveColor.darken()
          : hovered
          ? kButtonBorder
          : kActiveColor,
      path: Assets.icons.kblOpUser.path,
      size: 17,
    ),
  );
}
