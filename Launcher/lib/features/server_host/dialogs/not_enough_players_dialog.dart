import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';

class NotEnoughPlayersDialog extends StatefulWidget {
  const NotEnoughPlayersDialog({super.key});

  @override
  State<NotEnoughPlayersDialog> createState() => _NotEnoughPlayersDialogState();
}

class _NotEnoughPlayersDialogState extends State<NotEnoughPlayersDialog> {
  @override
  Widget build(BuildContext context) {
    return KyberContentDialog(
      title: Text(context.l10n.text('host.notEnoughPlayers.title')),
      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 300),
      content: Column(
        children: [
          Text(
            context.l10n.text('host.notEnoughPlayers.description'),
          ),
        ],
      ),
      actions: [
        KyberButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          text: context.l10n.text('common.cancel'),
        ),
        KyberButton(
          onPressed: () {
            Navigator.of(context).pop(true);
          },
          text: context.l10n.text('common.start'),
        ),
      ],
    );
  }
}
