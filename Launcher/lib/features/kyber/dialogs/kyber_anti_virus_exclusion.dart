import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/core/services/path_launcher_service.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';

class KyberAntiVirusExclusion extends StatefulWidget {
  const KyberAntiVirusExclusion({super.key});

  @override
  State<KyberAntiVirusExclusion> createState() =>
      _KyberAntiVirusExclusionState();
}

class _KyberAntiVirusExclusionState extends State<KyberAntiVirusExclusion> {
  @override
  Widget build(BuildContext context) {
    return KyberContentDialog(
      constraints: const BoxConstraints(
        maxWidth: 800,
        maxHeight: 500,
      ),
      title: const Text('Failed to launch game'),
      content: Column(
        children: [
          Text(
            'It seems that your antivirus is blocking Kyber Launcher from launching the game. ',
            style: FluentTheme.of(context).typography.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 15),
          Text(
            'Try making the following folder an exclusion in your anti-virus:',
          ),
          Text(FileHelper.getArmchairDirectory().path),
          const SizedBox(height: 10),
          Text('You can find that option here: Windows settings:'),
          const Text(
            'Settings -> Update & Security -> Windows Security -> Virus & Threat Protection -> Manage Settings -> Add or Remove Exclusions',
          ),
          const SizedBox(height: 20),
          Text(
            'If you need help, please refer to the documentation or contact support.',
            style: FluentTheme.of(context).typography.body,
          ),
        ],
      ),
      actions: [
        KyberButton(
          text: 'CLOSE',
          onPressed: () => Navigator.of(context).pop(),
        ),
        KyberButton(
          text: 'OPEN FOLDER',
          onPressed: () async {
            final directory = FileHelper.getArmchairDirectory().path;

            try {
              await PathLauncherService.openDirectory(directory);
            } catch (e) {
              NotificationService.error(message: 'Failed to open folder: $e');
            }
          },
        ),
        KyberButton(
          text: 'COPY FOLDER PATH',
          onPressed: () {
            final directory = FileHelper.getArmchairDirectory().path;

            Clipboard.setData(ClipboardData(text: directory));
          },
        ),
      ],
    );
  }
}
