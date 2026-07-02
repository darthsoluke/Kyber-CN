import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/features/map_rotation/models/map_rotation_entry.dart';
import 'package:kyber_launcher/features/server_browser/dialogs/load_map_dialog.dart';
import 'package:kyber_launcher/features/server_host/dialogs/not_enough_players_dialog.dart';
import 'package:kyber_launcher/features/server_host/providers/host_collection_cubit.dart';
import 'package:kyber_launcher/features/server_moderation/dialogs/moderation_input_dialog.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_cubit.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class IngameActions extends StatelessWidget {
  const IngameActions({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KyberTable(
      itemStyle: const TextStyle(fontSize: 17),
      items: [
        _buttonItem(
          context,
          title: l10n.text('host.ingame.startGame'),
          text: l10n.text('common.start'),
          onClick: () async {
            final cubit = context.read<ModerationCubit>();
            if (cubit.state.players.length < 2) {
              final result = await showKyberDialog(
                context: context,
                builder: (context) => const NotEnoughPlayersDialog(),
              );
              if (result == null || result != true) {
                return;
              }
            }

            if (!context.mounted) {
              return;
            }

            context.read<ModerationCubit>().sendCommand('/Kyber.startgame');
          },
        ),
        _buttonItem(
          context,
          title: l10n.text('host.ingame.skipMap'),
          text: l10n.text('common.skip'),
          onClick: () {
            context.read<ModerationCubit>().sendCommand('/Kyber.restart');
          },
        ),
        _buttonItem(
          context,
          title: l10n.text('host.ingame.changeMap'),
          text: l10n.text('common.change'),
          onClick: () async {
            final result = await showKyberDialog<MapRotationEntry>(
              context: context,
              builder: (_) => BlocProvider.value(
                value: context.read<HostCollectionCubit>(),
                child: const LoadMapDialog(),
              ),
            );

            if (result == null) {
              return;
            }

            if (!context.mounted) {
              return;
            }

            context.read<ModerationCubit>().sendCommand(
              '/Kyber.LoadLevel ${result.map} ${result.mode}',
            );
          },
        ),
        _buttonItem(
          context,
          title: l10n.text('host.ingame.pauseTimer'),
          text: l10n.text('common.pause'),
          onClick: () {
            context.read<ModerationCubit>().sendCommand('/Kyber.ToggleTimer');
          },
        ),
        _buttonItem(
          context,
          title: l10n.text('host.ingame.broadcastMessage'),
          text: l10n.text('host.ingame.send'),
          onClick: () async {
            final message = await showKyberDialog<String?>(
              context: context,
              builder: (_) => ModerationInputDialog(
                title: l10n.text('host.ingame.broadcastDialogTitle'),
                prompt: l10n.text('host.ingame.broadcastPrompt'),
                placeholder: l10n.text('host.ingame.messagePlaceholder'),
                submitText: l10n.text('host.ingame.send'),
              ),
            );

            if (message == null || message.trim().isEmpty) {
              return;
            }

            if (!context.mounted) {
              return;
            }

            context.read<ModerationCubit>().sendCommand(message);
          },
        ),
        _buttonItem(
          context,
          title: l10n.text('host.ingame.shuffleTeams'),
          text: l10n.text('host.ingame.shuffle'),
          onClick: () => context.read<ModerationCubit>().shuffleTeams(),
        ),
        _buttonItem(
          context,
          title: l10n.text('host.ingame.swapAllTeams'),
          text: l10n.text('host.ingame.swap'),
          onClick: () => context.read<ModerationCubit>().swapAllTeams(),
        ),
        _buttonItem(
          context,
          title: l10n.text('host.ingame.refreshServerState'),
          text: l10n.text('common.refresh'),
          onClick: () async {
            final cubit = context.read<ModerationCubit>();
            if (cubit.state.localControl) {
              await cubit.refreshLocalState();
            }
          },
        ),
      ],
    );
  }

  KyberTableItem<Object?> _buttonItem(
    BuildContext context, {
    required String title,
    required String text,
    required VoidCallback onClick,
  }) {
    return KyberTableItem.custom(
      title: title,
      builder: (_) => Align(
        alignment: Alignment.centerRight,
        child: KyberButton(
          text: text,
          fontSize: 14,
          onPressed: onClick,
        ),
      ),
    );
  }
}
