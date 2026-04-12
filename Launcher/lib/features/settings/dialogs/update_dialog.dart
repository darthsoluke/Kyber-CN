import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/services/module_version_service.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/core/services/windows_utils.dart';
import 'package:kyber_launcher/features/settings/dialogs/chromium_download_dialog.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';
import 'package:url_launcher/url_launcher_string.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    this.forceInstall = false,
    this.module = VersionModule.installer,
    super.key,
  });

  final VersionModule module;
  final bool forceInstall;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool installing = false;
  bool isCompMode = false;
  int total = 0;
  int current = 0;

  @override
  void initState() {
    if (WindowsUtils.isWindowsCompMode()) {
      isCompMode = true;
    } else if (widget.forceInstall) {
      startDownload();
    }

    super.initState();
  }

  void startDownload() async {
    if (installing) {
      return;
    }

    if (ModuleVersionService().isStandalone() &&
        widget.module != VersionModule.module) {
      NotificationService.showNotification(
        message:
            'Automatic updates are not supported in the standalone version.',
      );
      await Future.delayed(const Duration(seconds: 2));
      await launchUrlString('https://github.com/ArmchairDevelopers/KyberV2');
      return;
    }

    setState(() {
      installing = true;
      total = 0;
      current = 0;
    });
    if (widget.module == VersionModule.installer) {
      NotificationService.showNotification(message: 'Installing update...');
    }

    try {
      await ModuleVersionService().updateVersion(
        module: widget.module,
        onProgress: (current, total) {
          if (!mounted) {
            return;
          }

          setState(() {
            this.current = current;
            this.total = total;
          });
        },
      );

      if (!mounted) {
        return;
      }

      if (widget.module == VersionModule.module) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => installing = false);
      }

      NotificationService.error(
        message:
            'Failed to update ${widget.module == VersionModule.module ? 'Module' : 'Launcher'}: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return KyberContentDialog(
      title: Text(
        '${widget.module == VersionModule.module ? 'Module' : 'Launcher'} Update'
            .toUpperCase(),
      ),
      constraints: const BoxConstraints(
        maxWidth: 600,
        maxHeight: 400,
      ),
      actions: [
        KyberButton(
          onPressed: installing ? null : () => Navigator.pop(context),
          text: 'Ignore',
        ),
        KyberButton(
          onPressed: !installing ? startDownload : null,
          text: 'Install',
        ),
      ],
      content: SizedBox(
        height: 400,
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: installing
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.center,
            children: [
              if (installing) ...[
                const SizedBox(
                  height: 20,
                ),
                Text(
                  (total != 0 && current >= total)
                      ? 'Extracting update...'
                      : 'Downloading update... (${total != 0 ? (current / total * 100).toStringAsFixed(0) : 0}%)',
                  style: const TextStyle(
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 300,
                  child: ProgressBar(
                    value: total == 0 ? 0 : (current / total) * 100,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${formatBytes(current, 1)}/${formatBytes(total, 1)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    color: kWhiteColor,
                  ),
                ),
              ],
              if (!installing) ...[
                if (isCompMode) ...[
                  const Text(
                    'You are running the launcher in compatibility mode. This may cause issues with the update process.',
                  ),
                  const Text(
                    'We recommend to disable compatibility for updates.',
                  ),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'A new version of the launcher is available!',
                  style: TextStyle(
                    fontSize: 15,
                  ),
                ),
                //const Text(
                //  'Changelog:',
                //  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                //),
                //const SizedBox(height: 16),
                //MarkdownBody(
                //  data: 'Dummy Changelog\n\n[View Dummy](#)',
                //  onTapLink: (String text, String? href, String title) {
                //    if (href == null || href == '#') {
                //      return;
                //    }
                //    launchUrlString(href);
                //  },
                //),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
