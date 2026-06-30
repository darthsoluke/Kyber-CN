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
  final int port;
}

class LanDirectConnectDialog extends StatefulWidget {
  const LanDirectConnectDialog({super.key});

  @override
  State<LanDirectConnectDialog> createState() => _LanDirectConnectDialogState();
}

class _LanDirectConnectDialogState extends State<LanDirectConnectDialog> {
  String host = '';
  String portText = '25200';

  void _submit() {
    final l10n = context.l10n;
    var hostValue = host.trim();
    var portValue = int.tryParse(portText.trim());

    // Allow paste of "ip:port" into the host field.
    if (hostValue.contains(':') && (portValue == null || portValue == 25200)) {
      final index = hostValue.lastIndexOf(':');
      final maybeHost = hostValue.substring(0, index).trim();
      final maybePort = int.tryParse(hostValue.substring(index + 1).trim());
      if (maybeHost.isNotEmpty &&
          maybePort != null &&
          maybePort > 0 &&
          maybePort <= 65535) {
        hostValue = maybeHost;
        portValue = maybePort;
      }
    }

    if (hostValue.isEmpty) {
      NotificationService.error(
        message: l10n.text('lan.directConnect.enterHost'),
      );
      return;
    }

    if (portValue == null || portValue <= 0 || portValue > 65535) {
      NotificationService.error(
        message: l10n.text('lan.directConnect.enterValidPort'),
      );
      return;
    }

    Navigator.of(context).pop(
      LanDirectConnectResult(
        host: hostValue,
        port: portValue,
      ),
    );
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
            style: const TextStyle(color: kWhiteColor),
          ),
          const SizedBox(height: 14),
          KyberInput(
            placeholder: l10n.text('lan.directConnect.hostPlaceholder'),
            onChanged: (value) => setState(() => host = value),
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          KyberInput(
            placeholder: l10n.text('lan.directConnect.portPlaceholder'),
            initialValue: portText,
            onChanged: (value) => setState(() => portText = value),
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
