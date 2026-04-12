import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/features/map_rotation/models/map_rotation_entry.dart';
import 'package:kyber_launcher/features/server_browser/dialogs/load_map_dialog.dart';
import 'package:kyber_launcher/features/server_host/dialogs/not_enough_players_dialog.dart';
import 'package:kyber_launcher/features/server_host/providers/host_collection_cubit.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_cubit.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class IngameActions extends StatelessWidget {
  const IngameActions({super.key});

  @override
  Widget build(BuildContext context) {
    return KyberTable(
      itemStyle: const TextStyle(fontSize: 17),
      items: [
        KyberTableItem.button(
          title: context.l10n.text('host.ingame.startGame'),
          text: context.l10n.text('common.start'),
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

            context.read<ModerationCubit>().sendCommand('/Kyber.startgame');
          },
        ),
        KyberTableItem.button(
          title: context.l10n.text('host.ingame.skipMap'),
          text: context.l10n.text('common.skip'),
          onClick: () {
            context.read<ModerationCubit>().sendCommand('/Kyber.restart');
          },
        ),
        KyberTableItem.button(
          title: context.l10n.text('host.ingame.changeMap'),
          text: context.l10n.text('common.change'),
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

            context.read<ModerationCubit>().sendCommand(
              '/Kyber.LoadLevel ${result.map} ${result.mode}',
            );
          },
        ),
        KyberTableItem.button(
          title: context.l10n.text('host.ingame.pauseTimer'),
          text: context.l10n.text('common.pause'),
          onClick: () {
            context.read<ModerationCubit>().sendCommand('/Kyber.ToggleTimer');
          },
        ),
      ],
    );
  }
}
