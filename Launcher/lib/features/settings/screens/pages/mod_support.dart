import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/core.dart';
import 'package:kyber_launcher/features/frosty/dialogs/frosty_import_dialog.dart';
import 'package:kyber_launcher/features/mods/dialogs/move_directory_dialog.dart';
import 'package:kyber_launcher/features/settings/screens/settings.dart';
import 'package:kyber_launcher/main.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class ModSupport extends StatelessWidget {
  const ModSupport({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SuperListView(
      children: [
        SettingsHeader(title: l10n.text('settings.mods.header')),
        HiveListener(
          box: box,
          keys: ['enabledPreloadMods'],
          builder: (_) => KyberTable(
            items: [
              KyberTableItem.button(
                title: l10n.text('settings.changeModDirectory'),
                text: l10n.text('settings.newDirectory'),
                onClick: () => showKyberDialog(
                  builder: (_) => const MoveModsDirectoryDialog(),
                  context: context,
                ),
              ),
              KyberTableItem.button(
                title: l10n.text('settings.frostyConverter'),
                text: l10n.text('settings.convertYourPacks'),
                onClick: () => showKyberDialog(
                  builder: (_) => const FrostyImportDialog(),
                  context: context,
                ),
              ),
              KyberTableItem.switchButton(
                title: l10n.text('settings.kyberPreloadedMods'),
                value: Preferences.general.enabledPreloadMods,
                onChange: (bool value) {
                  Preferences.general.enabledPreloadMods = value;
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
