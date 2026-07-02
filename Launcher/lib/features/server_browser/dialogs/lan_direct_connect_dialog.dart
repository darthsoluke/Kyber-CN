import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class LanDirectConnectResult {
  LanDirectConnectResult({
    required this.host,
    required this.port,
  });

  final String host;
  final int? port;
}

class LanDirectConnectDialog extends StatefulWidget {
  const LanDirectConnectDialog({super.key});

  @override
  State<LanDirectConnectDialog> createState() => _LanDirectConnectDialogState();
}

class _LanDirectConnectDialogState extends State<LanDirectConnectDialog> {
  String address = '';

  void _submit() {
    final l10n = context.l10n;
    final parsed = _parseAddress(address);

    if (parsed == null) {
      NotificationService.error(
        message: l10n.text('lan.directConnect.enterValidAddress'),
      );
      return;
    }

    Navigator.of(context).pop(
      LanDirectConnectResult(
        host: parsed.$1,
        port: parsed.$2,
      ),
    );
  }

  (String, int?)? _parseAddress(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) {
      return null;
    }

    var host = trimmed;
    int? port;
    if (trimmed.contains(':')) {
      final index = trimmed.lastIndexOf(':');
      host = trimmed.substring(0, index).trim();
      port = int.tryParse(trimmed.substring(index + 1).trim());
      if (host.isEmpty || port == null || port <= 0 || port > 65535) {
        return null;
      }
    }

    if (host.isEmpty) {
      return null;
    }
    return (host, port);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KyberContentDialog(
      title: Text(l10n.text('lan.directConnect.title')),
      constraints: const BoxConstraints(
        maxWidth: 600,
        maxHeight: 420,
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.text('lan.directConnect.description'),
            style: const TextStyle(color: kWhiteColor, height: 1.25),
          ),
          const SizedBox(height: 14),
          KyberInput(
            placeholder: l10n.text('lan.directConnect.addressPlaceholder'),
            onChanged: (value) => setState(() => address = value),
            onFieldSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        KyberButton(
          text: l10n.text('common.cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        KyberButton(
          text: l10n.text('common.continue'),
          onPressed: _submit,
        ),
      ],
    );
  }
}
