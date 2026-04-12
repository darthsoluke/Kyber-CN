import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/server_settings_box.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class ServerSettings extends StatelessWidget {
  const ServerSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SuperListView(
      children: [
        KyberSectionDropdown(
          initialExpanded: true,
          title: l10n.text('host.server.section'),
          child: KyberTable(
            itemStyle: const TextStyle(fontSize: 17),
            items: [
              KyberTableItem.custom(
                title: l10n.text('host.authMode'),
                builder: (hovered) {
                  return FormBuilderField<bool>(
                    name: 'onlineMode',
                    builder: (field) {
                      final value = field.value ?? true;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => field.didChange(!value),
                        child: KyberTableSwitch(
                          hover: hovered,
                          value: value,
                          disabledText: l10n.text('host.offline'),
                          enabledText: l10n.text('host.online'),
                          onChanged: (value) => field.didChange(value),
                        ),
                      );
                    },
                  );
                },
              ),
              KyberTableItem.custom(
                title: l10n.text('host.port'),
                builder: (hovered) {
                  return SizedBox(
                    width: 140,
                    child: KyberFormInputField(
                      name: 'serverPort',
                      placeholder: l10n.text('host.portPlaceholder'),
                      validator: (value) {
                        final port = int.tryParse((value ?? '').toString());
                        if (port == null || port <= 0 || port > 65535) {
                          return l10n.text('host.invalidPort');
                        }

                        return null;
                      },
                    ),
                  );
                },
              ),
              KyberTableItem.custom(
                title: l10n.text('host.maxPlayers'),
                builder: (hovered) {
                  return FormBuilderField<int>(
                    name: 'maxPlayers',
                    builder: (field) {
                      return KyberTableSlider(
                        hover: hovered,
                        min: 2,
                        max: 64,
                        value: field.value!,
                        onChanged: (value) {
                          field.didChange(value);
                          final maxPlayersField = hostingForm
                              .currentState!
                              .fields['maxSpectators']!;
                          final maxPlayers = maxPlayersField.value as int;
                          if (maxPlayers + value > 64) {
                            hostingForm.currentState!.fields['maxSpectators']!
                                .setValue(64 - value);
                          }
                        },
                      );
                    },
                  );
                },
              ),
              KyberTableItem.custom(
                title: l10n.text('host.maxSpectators'),
                builder: (hovered) {
                  return FormBuilderField<int>(
                    name: 'maxSpectators',
                    builder: (field) {
                      return KyberTableSlider(
                        hover: hovered,
                        min: 0,
                        max: 62,
                        value: field.value!,
                        onChanged: (value) {
                          field.didChange(value);
                          final maxPlayersField =
                              hostingForm.currentState!.fields['maxPlayers']!;
                          final maxPlayers = maxPlayersField.value as int;
                          if (maxPlayers + value > 64) {
                            hostingForm.currentState!.fields['maxPlayers']!
                                .setValue(64 - value);
                          }
                        },
                      );
                    },
                  );
                },
              ),
              KyberTableItem.switchButton(
                title: l10n.text('host.proximityChat'),
                value: true,
                onChange: (value) async {
                  NotificationService.notImplemented();
                },
              ),
            ],
          ),
        ),
        KyberSectionDropdown(
          initialExpanded: true,
          title: l10n.text('host.privacy.section'),
          child: KyberTable(
            itemStyle: const TextStyle(fontSize: 17),
            items: [
              KyberTableItem.custom(
                title: l10n.text('host.password'),
                builder: (hovered) {
                  return KyberFormInputField(
                    name: 'password',
                    isSensitive: true,
                    placeholder: l10n.text('host.passwordPlaceholder'),
                    validator: FormBuilderValidators.compose(
                      [
                        FormBuilderValidators.maxLength(
                          25,
                          checkNullOrEmpty: false,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
