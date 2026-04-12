import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';

class ModLimitDialog extends StatelessWidget {
  const ModLimitDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KyberContentDialog(
      title: Text(l10n.text('modLimit.title')),
      constraints: const BoxConstraints(
        maxWidth: 600,
        maxHeight: 400,
      ),
      content: Text(
        l10n.text('modLimit.description'),
        textAlign: TextAlign.center,
      ),
      actions: [
        KyberButton(
          text: l10n.text('common.okay'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
