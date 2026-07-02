import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/server_settings_box.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_cubit.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class IngameSettings extends StatelessWidget {
  const IngameSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KyberTable(
      itemStyle: const TextStyle(fontSize: 17),
      items: [
        KyberTableItem.custom(
          title: l10n.text('host.ingame.shuffleTeams'),
          onClick: () {
            final value =
                !(hostingForm.currentState!.fields['shuffleTeams']!.value
                    as bool);
            hostingForm.currentState?.fields['shuffleTeams']?.didChange(value);
            context.read<ModerationCubit>().sendCommand(
              '/Kyber.EnableShuffleTeams ${value ? '1' : '0'}',
            );
          },
          builder: (hovered) {
            return FormBuilderField<bool>(
              name: 'shuffleTeams',
              initialValue: false,
              builder: (field) {
                return KyberTableSwitch(
                  value: field.value,
                  hover: hovered,
                  onChanged: (value) {},
                );
              },
            );
          },
        ),
        KyberTableItem.custom(
          title: l10n.text('host.ingame.botDifficulty'),
          builder: (hovered) {
            return FormBuilderField<int>(
              name: 'botDifficulty',
              initialValue: 3,
              builder: (field) {
                return KyberTableSelector<int>(
                  items: [
                    KyberSelectorItem(
                      title: l10n.text('host.ingame.difficultyEasy'),
                      value: 12,
                    ),
                    KyberSelectorItem(
                      title: l10n.text('host.ingame.difficultyMedium'),
                      value: 9,
                    ),
                    KyberSelectorItem(
                      title: l10n.text('host.ingame.difficultyHard'),
                      value: 6,
                    ),
                    KyberSelectorItem(
                      title: l10n.text('host.ingame.difficultyKnight'),
                      value: 3,
                    ),
                    KyberSelectorItem(
                      title: l10n.text('host.ingame.difficultyMaster'),
                      value: 0,
                    ),
                  ],
                  value: field.value,
                  hover: hovered,
                  onChanged: (value) {
                    field.didChange(value);
                    context.read<ModerationCubit>().sendCommand(
                      '/AutoPlayers.AimNoiseScale $value',
                    );
                  },
                );
              },
            );
          },
        ),
        KyberTableItem.custom(
          title: l10n.text('host.ingame.botsTeam1'),
          builder: (hovered) {
            return FormBuilderField<int>(
              name: 'botsTeam1',
              initialValue: 0,
              builder: (field) {
                return KyberTableSlider(
                  min: 0,
                  max: 32,
                  value: field.value!,
                  hover: hovered,
                  onChanged: (value) {
                    field.didChange(value);
                    context.read<ModerationCubit>().botChangeStream!.add((
                      1,
                      value,
                    ));
                  },
                );
              },
            );
          },
        ),
        KyberTableItem.custom(
          title: l10n.text('host.ingame.botsTeam2'),
          builder: (hovered) {
            return FormBuilderField<int>(
              name: 'botsTeam2',
              initialValue: 0,
              builder: (field) {
                return KyberTableSlider(
                  min: 0,
                  max: 32,
                  value: field.value!,
                  hover: hovered,
                  onChanged: (value) {
                    field.didChange(value);
                    context.read<ModerationCubit>().botChangeStream!.add((
                      2,
                      value,
                    ));
                  },
                );
              },
            );
          },
        ),
        KyberTableItem.custom(
          title: l10n.text('host.ingame.freezeBots'),
          onClick: () {
            final value =
                !(hostingForm.currentState!.fields['freezeBots']!.value
                    as bool);
            hostingForm.currentState?.fields['freezeBots']?.didChange(value);
            context.read<ModerationCubit>().sendCommand(
              '/AutoPlayers.UpdateAI ${value ? '0' : '1'}',
            );
          },
          builder: (hovered) {
            return FormBuilderField<bool>(
              name: 'freezeBots',
              initialValue: false,
              builder: (field) {
                return KyberTableSwitch(
                  value: field.value,
                  hover: hovered,
                  onChanged: (value) {},
                );
              },
            );
          },
        ),
        KyberTableItem.custom(
          title: l10n.text('host.ingame.botsIgnorePlayers'),
          onClick: () {
            final value =
                !(hostingForm.currentState!.fields['botsIgnorePlayers']!.value
                    as bool);
            hostingForm.currentState?.fields['botsIgnorePlayers']?.didChange(
              value,
            );
            context.read<ModerationCubit>().sendCommand(
              '/AutoPlayers.IgnoreHumanPlayers ${value ? '1' : '0'}',
            );
          },
          builder: (hovered) {
            return FormBuilderField<bool>(
              name: 'botsIgnorePlayers',
              initialValue: false,
              builder: (field) {
                return KyberTableSwitch(
                  value: field.value,
                  hover: hovered,
                  onChanged: (value) {},
                );
              },
            );
          },
        ),
      ],
    );
  }
}
