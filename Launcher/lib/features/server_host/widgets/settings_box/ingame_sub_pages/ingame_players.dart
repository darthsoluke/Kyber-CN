import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/server_settings_box.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_cubit.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class IngamePlayers extends StatelessWidget {
  const IngamePlayers({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KyberTable(
      itemStyle: const TextStyle(fontSize: 17),
      items: [
        KyberTableItem.custom(
          title: l10n.text('host.ingame.friendlyFire'),
          onClick: () {
            final value =
                !(hostingForm.currentState!.fields['friendlyFire']!.value
                    as bool);
            hostingForm.currentState?.fields['friendlyFire']?.didChange(value);
            context.read<ModerationCubit>().sendCommand(
              '/SyncedGame.EnableFriendlyFire ${value ? '1' : '0'}',
            );
          },
          builder: (hovered) {
            return FormBuilderField<bool>(
              initialValue: false,
              builder: (field) {
                return KyberTableSwitch(
                  onChanged: (value) {},
                  value: field.value,
                  hover: hovered,
                );
              },
              name: 'friendlyFire',
            );
          },
        ),
        KyberTableItem.custom(
          title: l10n.text('host.ingame.disableRegeneration'),
          onClick: () {
            final value =
                !(hostingForm.currentState!.fields['disableRegeneration']!.value
                    as bool);
            hostingForm.currentState?.fields['disableRegeneration']?.didChange(
              value,
            );
            context.read<ModerationCubit>().sendCommand(
              '/SyncedGame.DisableRegenerateHealth ${value ? '1' : '0'}',
            );
          },
          builder: (hovered) {
            return FormBuilderField<bool>(
              initialValue: false,
              builder: (field) {
                return KyberTableSwitch(
                  onChanged: (value) {},
                  value: field.value,
                  hover: hovered,
                );
              },
              name: 'disableRegeneration',
            );
          },
        ),
      ],
    );
  }
}
