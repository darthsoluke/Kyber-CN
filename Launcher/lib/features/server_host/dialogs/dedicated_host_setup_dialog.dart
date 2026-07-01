import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/i18n/app_localizations.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/features/server_host/services/dedicated_host_user_config_service.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class DedicatedHostSetupDialog extends StatefulWidget {
  const DedicatedHostSetupDialog({super.key});

  @override
  State<DedicatedHostSetupDialog> createState() =>
      _DedicatedHostSetupDialogState();
}

class _DedicatedHostSetupDialogState extends State<DedicatedHostSetupDialog> {
  final _gamePathController = TextEditingController();
  final _runtimeRootController = TextEditingController();
  final _denuvoTokenController = TextEditingController();
  final DedicatedHostUserConfigService _service = sl
      .get<DedicatedHostUserConfigService>();

  bool _loading = true;
  bool _saving = false;
  bool _hasCredentials = false;
  bool _hasDenuvoToken = false;
  DedicatedHostLicenseMode _licenseMode = DedicatedHostLicenseMode.refresh;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _gamePathController.dispose();
    _runtimeRootController.dispose();
    _denuvoTokenController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final hasCredentials = await _service.hasCredentials();
    final hasDenuvoToken = await _service.hasDenuvoToken();
    final detectedGamePath = _service.gamePath.isEmpty
        ? _service.detectGamePath()
        : _service.gamePath;
    final detectedRuntimeRoot = _service.runtimeRoot.isEmpty
        ? _service.detectRuntimeRoot()
        : _service.runtimeRoot;

    if (!mounted) {
      return;
    }

    setState(() {
      _gamePathController.text = detectedGamePath ?? '';
      _runtimeRootController.text = detectedRuntimeRoot ?? '';
      _hasCredentials = hasCredentials;
      _hasDenuvoToken = hasDenuvoToken;
      _licenseMode = _service.licenseMode;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return KyberContentDialog(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
      title: Text(l10n.text('settings.dedicatedHost.dialogTitle')),
      content: _loading
          ? const Center(child: ProgressRing())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.text('settings.dedicatedHost.dialogDescription'),
                    style: FluentTheme.of(context).typography.body?.copyWith(
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _InfoPanel(
                    title: l10n.text('settings.dedicatedHost.authSession'),
                    body: l10n.text('settings.dedicatedHost.authSessionHint'),
                    action: _hasCredentials
                        ? KyberButton(
                            text: l10n.text(
                              'settings.dedicatedHost.clearLegacyCredentials',
                            ),
                            onPressed: _saving ? null : _clearCredentials,
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _InputLabel(
                    text: l10n.text('settings.dedicatedHost.licenseMode'),
                  ),
                  ComboBox<DedicatedHostLicenseMode>(
                    value: _licenseMode,
                    isExpanded: true,
                    items: const [DedicatedHostLicenseMode.refresh]
                        .map(
                          (mode) => ComboBoxItem<DedicatedHostLicenseMode>(
                            value: mode,
                            child: Text(_licenseModeLabel(l10n, mode)),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.text('settings.dedicatedHost.licenseModeHint'),
                    style: FluentTheme.of(context).typography.caption?.copyWith(
                      color: Colors.white.withValues(alpha: .64),
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InputLabel(
                    text: _hasDenuvoToken
                        ? l10n.text(
                            'settings.dedicatedHost.denuvoTokenPreserve',
                          )
                        : l10n.text('settings.dedicatedHost.denuvoToken'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: KyberInput(
                          controller: _denuvoTokenController,
                          isSensitive: true,
                          placeholder: _hasDenuvoToken
                              ? l10n.text(
                                  'settings.dedicatedHost.denuvoTokenOptional',
                                )
                              : l10n.text(
                                  'settings.dedicatedHost.'
                                  'denuvoTokenPlaceholder',
                                ),
                        ),
                      ),
                      if (_hasDenuvoToken) ...[
                        const SizedBox(width: 10),
                        KyberButton(
                          text: l10n.text(
                            'settings.dedicatedHost.clearDenuvoToken',
                          ),
                          onPressed: _saving ? null : _clearDenuvoToken,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InputLabel(
                    text: l10n.text('settings.dedicatedHost.gamePath'),
                  ),
                  _PathInputRow(
                    controller: _gamePathController,
                    placeholder: l10n.text(
                      'settings.dedicatedHost.gamePathPlaceholder',
                    ),
                    browseText: l10n.text('common.select'),
                    onBrowse: _pickGamePath,
                  ),
                  const SizedBox(height: 12),
                  _InputLabel(
                    text: l10n.text('settings.dedicatedHost.runtimeRoot'),
                  ),
                  _PathInputRow(
                    controller: _runtimeRootController,
                    placeholder: l10n.text(
                      'settings.dedicatedHost.runtimeRootPlaceholder',
                    ),
                    browseText: l10n.text('common.select'),
                    onBrowse: _pickRuntimeRoot,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.text('settings.dedicatedHost.runtimeHint'),
                    style: FluentTheme.of(context).typography.caption?.copyWith(
                      color: Colors.white.withValues(alpha: .64),
                      height: 1.2,
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _message!,
                      style: FluentTheme.of(context).typography.body?.copyWith(
                        color: Colors.red,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      actions: [
        KyberButton(
          text: l10n.text('common.cancel'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        KyberButton(
          text: l10n.text('settings.dedicatedHost.autoDetect'),
          onPressed: _saving ? null : _autoDetect,
        ),
        KyberButton(
          text: l10n.text('common.save'),
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Future<void> _pickGamePath() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['exe'],
      dialogTitle: 'Select starwarsbattlefrontii.exe',
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) {
      return;
    }

    setState(() => _gamePathController.text = path);
  }

  Future<void> _pickRuntimeRoot() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select dedicated_runtime directory',
    );
    if (path == null || !mounted) {
      return;
    }

    setState(() => _runtimeRootController.text = path);
  }

  void _autoDetect() {
    final gamePath = _service.detectGamePath();
    final runtimeRoot = _service.detectRuntimeRoot();
    setState(() {
      if (gamePath != null) {
        _gamePathController.text = gamePath;
      }
      if (runtimeRoot != null) {
        _runtimeRootController.text = runtimeRoot;
      }
      _message = null;
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    setState(() {
      _saving = true;
      _message = null;
    });

    try {
      _service.gamePath = _gamePathController.text;
      _service.runtimeRoot = _runtimeRootController.text;
      await _service.saveLicenseSettings(
        mode: DedicatedHostLicenseMode.refresh,
        denuvoToken: _denuvoTokenController.text,
        preserveDenuvoToken:
            _hasDenuvoToken && _denuvoTokenController.text.trim().isEmpty,
      );
      final missing = await _service.missingLaunchRequirements();
      if (missing.isNotEmpty) {
        throw DedicatedHostConfigException(
          l10n.text(
            'settings.dedicatedHost.missing',
            params: {'items': missing.join(', ')},
          ),
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _message = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _clearCredentials() async {
    await _service.clearCredentials();
    if (!mounted) {
      return;
    }

    setState(() {
      _hasCredentials = false;
      _message = null;
    });
  }

  Future<void> _clearDenuvoToken() async {
    await _service.clearDenuvoToken();
    if (!mounted) {
      return;
    }

    setState(() {
      _hasDenuvoToken = false;
      _denuvoTokenController.clear();
      _message = null;
    });
  }

  String _licenseModeLabel(
    AppLocalizations l10n,
    DedicatedHostLicenseMode mode,
  ) {
    return switch (mode) {
      DedicatedHostLicenseMode.reuse => l10n.text(
        'settings.dedicatedHost.licenseModeReuse',
      ),
      DedicatedHostLicenseMode.refresh => l10n.text(
        'settings.dedicatedHost.licenseModeRefresh',
      ),
    };
  }
}

class _InputLabel extends StatelessWidget {
  const _InputLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: FluentTheme.of(context).typography.bodyStrong,
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.title,
    required this.body,
    this.action,
  });

  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: FluentTheme.of(context).typography.bodyStrong),
          const SizedBox(height: 6),
          Text(
            body,
            style: FluentTheme.of(context).typography.caption?.copyWith(
              color: Colors.white.withValues(alpha: .72),
              height: 1.25,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 10),
            action!,
          ],
        ],
      ),
    );
  }
}

class _PathInputRow extends StatelessWidget {
  const _PathInputRow({
    required this.controller,
    required this.placeholder,
    required this.browseText,
    required this.onBrowse,
  });

  final TextEditingController controller;
  final String placeholder;
  final String browseText;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: KyberInput(
            controller: controller,
            placeholder: placeholder,
          ),
        ),
        const SizedBox(width: 10),
        KyberButton(text: browseText, onPressed: onBrowse),
      ],
    );
  }
}
