import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class SakuraFrpSetupDialog extends StatefulWidget {
  const SakuraFrpSetupDialog({super.key});

  @override
  State<SakuraFrpSetupDialog> createState() => _SakuraFrpSetupDialogState();
}

class _SakuraFrpSetupDialogState extends State<SakuraFrpSetupDialog> {
  late bool enabled;
  late TextEditingController apiBaseUrlController;
  late TextEditingController apiTokenController;
  late TextEditingController nodeOverridesController;
  late TextEditingController manualEndpointsController;
  late TextEditingController cachedEndpointsController;

  @override
  void initState() {
    super.initState();
    enabled = Preferences.sakuraFrp.enabled;
    apiBaseUrlController = TextEditingController(
      text: Preferences.sakuraFrp.apiBaseUrl,
    );
    apiTokenController = TextEditingController(
      text: Preferences.sakuraFrp.apiToken,
    );
    nodeOverridesController = TextEditingController(
      text: Preferences.sakuraFrp.nodeHostOverrides,
    );
    manualEndpointsController = TextEditingController(
      text: Preferences.sakuraFrp.manualEndpoints,
    );
    cachedEndpointsController = TextEditingController(
      text: Preferences.sakuraFrp.cachedEndpoints,
    );
  }

  @override
  void dispose() {
    apiBaseUrlController.dispose();
    apiTokenController.dispose();
    nodeOverridesController.dispose();
    manualEndpointsController.dispose();
    cachedEndpointsController.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = context.l10n;
    final apiBaseUrl = apiBaseUrlController.text.trim();
    if (apiBaseUrl.isEmpty || Uri.tryParse(apiBaseUrl)?.hasScheme != true) {
      NotificationService.error(
        message: l10n.text('sakuraFrp.enterValidApiBaseUrl'),
      );
      return;
    }

    Preferences.sakuraFrp.enabled = enabled;
    Preferences.sakuraFrp.apiBaseUrl = apiBaseUrl;
    Preferences.sakuraFrp.apiToken = apiTokenController.text.trim();
    Preferences.sakuraFrp.nodeHostOverrides = nodeOverridesController.text;
    Preferences.sakuraFrp.manualEndpoints = manualEndpointsController.text;
    Preferences.sakuraFrp.cachedEndpoints = cachedEndpointsController.text;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KyberContentDialog(
      title: Text(l10n.text('sakuraFrp.dialogTitle')),
      constraints: const BoxConstraints(
        maxWidth: 720,
        maxHeight: 760,
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.text('sakuraFrp.description'),
              style: const TextStyle(
                color: kWhiteColor,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            _GuideCard(
              title: l10n.text('sakuraFrp.hostGuideTitle'),
              lines: [
                l10n.text('sakuraFrp.hostGuideGame'),
                l10n.text('sakuraFrp.hostGuideMetadata'),
                l10n.text('sakuraFrp.hostGuideClient'),
              ],
            ),
            const SizedBox(height: 14),
            Checkbox(
              checked: enabled,
              onChanged: (value) => setState(() => enabled = value ?? false),
              content: Text(l10n.text('sakuraFrp.enabled')),
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: l10n.text('sakuraFrp.apiBaseUrl'),
              child: KyberInput(
                controller: apiBaseUrlController,
                placeholder: 'https://api.natfrp.com/v4',
              ),
            ),
            const SizedBox(height: 12),
            _LabeledField(
              label: l10n.text('sakuraFrp.apiToken'),
              child: KyberInput(
                controller: apiTokenController,
                isSensitive: true,
                placeholder: l10n.text('sakuraFrp.apiTokenPlaceholder'),
              ),
            ),
            const SizedBox(height: 6),
            _HelpText(l10n.text('sakuraFrp.apiHelp')),
            const SizedBox(height: 12),
            _LabeledField(
              label: l10n.text('sakuraFrp.nodeOverrides'),
              child: _MultilineBox(
                controller: nodeOverridesController,
                placeholder: '1=idea-leaper-1.natfrp.io',
              ),
            ),
            const SizedBox(height: 6),
            _HelpText(l10n.text('sakuraFrp.nodeOverrideHelp')),
            const SizedBox(height: 12),
            _LabeledField(
              label: l10n.text('sakuraFrp.manualEndpoints'),
              child: _MultilineBox(
                controller: manualEndpointsController,
                placeholder: l10n.text('sakuraFrp.manualExample'),
              ),
            ),
            const SizedBox(height: 6),
            _HelpText(l10n.text('sakuraFrp.manualHelp')),
            const SizedBox(height: 12),
            _LabeledField(
              label: l10n.text('sakuraFrp.savedEndpoints'),
              child: _MultilineBox(
                controller: cachedEndpointsController,
                placeholder: l10n.text('sakuraFrp.savedEndpointsPlaceholder'),
              ),
            ),
            const SizedBox(height: 6),
            _HelpText(l10n.text('sakuraFrp.savedHelp')),
            const SizedBox(height: 12),
            Text(
              l10n.text('sakuraFrp.portHint'),
              style: const TextStyle(
                color: kInactiveColor,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
      actions: [
        KyberButton(
          text: l10n.text('common.cancel'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        KyberButton(
          text: l10n.text('common.save'),
          onPressed: _save,
        ),
      ],
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.title,
    required this.lines,
  });

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        border: Border.all(color: kDefaultActiveColor.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: kDefaultActiveColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final line in lines) ...[
            Text(
              line,
              style: const TextStyle(color: kWhiteColor, height: 1.25),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _HelpText extends StatelessWidget {
  const _HelpText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: kInactiveColor,
        height: 1.25,
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      textField: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: const TextStyle(
                color: kWhiteColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _MultilineBox extends StatelessWidget {
  const _MultilineBox({
    required this.controller,
    required this.placeholder,
  });

  final TextEditingController controller;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return TextBox(
      controller: controller,
      placeholder: placeholder,
      minLines: 3,
      maxLines: 5,
    );
  }
}
