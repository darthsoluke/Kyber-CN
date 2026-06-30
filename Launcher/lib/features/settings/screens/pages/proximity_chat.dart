import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/core/services/voip_service.dart';
import 'package:kyber_launcher/features/maxima/services/maxima_instance_service.dart';
import 'package:kyber_launcher/features/settings/screens/settings.dart';
import 'package:kyber_launcher/features/settings/widgets/voip_key_picker.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/main.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class ProximityChat extends StatelessWidget {
  const ProximityChat({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SuperListView(
      children: [
        SettingsHeader(title: l10n.text('settings.ingame.title')),
        HiveListener(
          box: box,
          keys: const ['ingameHotkeyEnabled'],
          builder: (context) {
            return KyberTable(
              items: [
                KyberTableItem.switchButton(
                  title: l10n.text('settings.ingameHotkey'),
                  value: Preferences.general.ingameHotkeyEnabled,
                  onChange: (value) async {
                    Preferences.general.ingameHotkeyEnabled = value;
                    if (sl.get<MaximaInstanceService>().hasInstances) {
                      NotificationService.showNotification(
                        message: l10n.text('settings.restartGameToApply'),
                      );
                    }
                  },
                  enabledText: l10n.text('common.enabled'),
                  disabledText: l10n.text('common.disabled'),
                ),
              ],
            );
          },
        ),
        SettingsHeader(title: l10n.text('settings.proximityChat.header')),
        ListenableBuilder(
          listenable: sl.get<VoipService>(),
          builder: (_, __) {
            final service = sl.get<VoipService>();

            final child = KyberTable(
              items: [
                KyberTableItem.switchButton(
                  title: l10n.text('settings.proximityChat'),
                  onChange: (value) => service.setVoiceChat(enabled: value),
                  value: service.isEnabled,
                ),
                KyberTableItem.switchButton(
                  title: l10n.text('settings.inputMode'),
                  onChange: (value) => service.setPushToTalk(enabled: value),
                  value: service.isPushToTalkEnabled,
                  disabledText: l10n.text('settings.openMic'),
                  enabledText: l10n.text('settings.pushToTalk'),
                ),
                if (service.isPushToTalkEnabled)
                  KyberTableItem.custom(
                    title: l10n.text('settings.pushToTalkKey'),
                    builder: (context) {
                      return CharKeyPicker(
                        value: VoipKeyResponse(
                          display: Preferences.general.pushToTalkKeyDisplay,
                          keyId: service.pushToTalkKey,
                        ),
                        onChanged: (k) => service.setPushToTalkKey(key: k),
                      );
                    },
                  ),
                KyberTableItem.slider(
                  title: l10n.text('settings.inputVolume'),
                  value: Preferences.general.defaultInputVolume,
                  onChanged: (value) async {
                    Preferences.general.defaultInputVolume = value;
                    service.setGameVoipSettings();
                  },
                  min: 0,
                  max: 100,
                ),
                KyberTableItem.slider(
                  title: l10n.text('settings.outputVolume'),
                  value: Preferences.general.defaultOutputVolume,
                  onChanged: (value) async {
                    Preferences.general.defaultOutputVolume = value;
                    service.setGameVoipSettings();
                  },
                  min: 0,
                  max: 100,
                ),
                KyberTableItem.selector(
                  title: l10n.text('settings.inputDevice'),
                  items: service.inputDevices.isEmpty
                      ? [
                          KyberSelectorItem(
                            title: l10n.text('settings.noDevicesFound'),
                            value: '',
                          ),
                        ]
                      : service.inputDevices.map((e) {
                          return KyberSelectorItem<String>(
                            title: e.name,
                            value: e.id,
                          );
                        }).toList(),
                  value: service.inputDevices.isEmpty
                      ? ''
                      : service.selectedInputDevice,
                  onChange: service.inputDevices.isEmpty
                      ? null
                      : (value) async {
                          Preferences.general.selectedInputDevice =
                              value as String;
                          service.setInputDevice(value);
                        },
                ),
                KyberTableItem.selector(
                  title: l10n.text('settings.outputDevice'),
                  items: service.outputDevices.isEmpty
                      ? [
                          KyberSelectorItem(
                            title: l10n.text('settings.noDevicesFound'),
                            value: '',
                          ),
                        ]
                      : service.outputDevices.map((e) {
                          return KyberSelectorItem<String>(
                            title: e.name,
                            value: e.id,
                          );
                        }).toList(),
                  value: service.outputDevices.isEmpty
                      ? ''
                      : service.selectedOutputDevice,
                  onChange: service.outputDevices.isEmpty
                      ? null
                      : (dynamic value) async {
                          service.setOutputDevice(value as String);
                        },
                ),
              ],
            );

            return child;
          },
        ),
      ],
    );
  }
}
