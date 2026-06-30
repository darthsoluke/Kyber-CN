import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/features/server_host/models/host_start_progress_event.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';

class HostStartProgressDialog extends StatefulWidget {
  const HostStartProgressDialog({
    required this.titleKey,
    required this.onStart,
    this.onConfigure,
    this.onCleanup,
    super.key,
  });

  final String titleKey;
  final Future<void> Function(HostStartProgressSink progress) onStart;
  final Future<bool> Function()? onConfigure;
  final Future<void> Function(HostStartProgressSink progress)? onCleanup;

  @override
  State<HostStartProgressDialog> createState() =>
      _HostStartProgressDialogState();
}

class _HostStartProgressDialogState extends State<HostStartProgressDialog> {
  final List<HostStartProgressEvent> _events = [];
  bool _running = true;
  bool _configuring = false;
  bool _cleaning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run({bool retry = false}) async {
    setState(() {
      _running = true;
      if (retry) {
        _events.clear();
      }
    });

    _add(
      HostStartProgressEvent(
        messageKey: retry
            ? 'host.progress.retrying'
            : 'host.progress.dialogOpened',
      ),
    );

    try {
      await widget.onStart(_add);
      if (!_hasTerminalEvent) {
        _add(
          HostStartProgressEvent(
            messageKey: 'host.progress.completed',
            status: HostStartProgressStatus.success,
          ),
        );
      }
    } on Object catch (e) {
      _add(
        HostStartProgressEvent(
          messageKey: 'host.progress.failedWithMessage',
          params: {'message': e},
          status: HostStartProgressStatus.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  bool get _hasTerminalEvent => _events.any(
    (event) =>
        event.status == HostStartProgressStatus.success ||
        event.status == HostStartProgressStatus.error,
  );

  void _add(HostStartProgressEvent event) {
    if (!mounted) {
      return;
    }

    setState(() => _events.add(event));
  }

  Future<void> _changeConfiguration() async {
    final onConfigure = widget.onConfigure;
    if (onConfigure == null || _running || _configuring) {
      return;
    }

    setState(() => _configuring = true);
    try {
      final changed = await onConfigure();
      _add(
        HostStartProgressEvent(
          messageKey: changed
              ? 'host.progress.configurationUpdated'
              : 'host.progress.configurationCancelled',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _configuring = false);
      }
    }
  }

  Future<void> _cleanupOrphans() async {
    final onCleanup = widget.onCleanup;
    if (onCleanup == null || _running || _cleaning) {
      return;
    }

    setState(() => _cleaning = true);
    _add(
      HostStartProgressEvent(
        messageKey: 'host.progress.cleanupStarted',
      ),
    );
    try {
      await onCleanup(_add);
      _add(
        HostStartProgressEvent(
          messageKey: 'host.progress.cleanupCompleted',
          status: HostStartProgressStatus.success,
        ),
      );
    } on Object catch (e) {
      _add(
        HostStartProgressEvent(
          messageKey: 'host.progress.cleanupFailedWithMessage',
          params: {'message': e},
          status: HostStartProgressStatus.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _cleaning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final failed = _events.any(
      (event) => event.status == HostStartProgressStatus.error,
    );
    final completed = _events.any(
      (event) => event.status == HostStartProgressStatus.success,
    );

    return KyberContentDialog(
      title: Text(l10n.text(widget.titleKey)),
      constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProgressSummary(
            running: _running,
            failed: failed,
            completed: completed,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .34),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .14),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ListView.builder(
                itemCount: _events.length,
                itemBuilder: (context, index) {
                  return _ProgressEventRow(event: _events[index]);
                },
              ),
            ),
          ),
        ],
      ),
      actions: _buildActions(
        context,
        completed: completed,
        failed: failed,
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context, {
    required bool completed,
    required bool failed,
  }) {
    final l10n = context.l10n;
    if (failed && !_running) {
      return [
        if (widget.onConfigure != null)
          KyberButton(
            text: l10n.text('host.progress.changeDedicatedConfig'),
            onPressed: _configuring || _cleaning ? null : _changeConfiguration,
          ),
        if (widget.onCleanup != null)
          KyberButton(
            text: l10n.text('host.progress.cleanupOrphans'),
            onPressed: _configuring || _cleaning ? null : _cleanupOrphans,
          ),
        KyberButton(
          text: l10n.text('host.progress.retry'),
          onPressed: _configuring || _cleaning ? null : () => _run(retry: true),
        ),
        KyberButton(
          text: l10n.text('common.close'),
          onPressed: _configuring || _cleaning
              ? null
              : () => Navigator.of(context).pop(),
        ),
      ];
    }

    return [
      KyberButton(
        text: l10n.text(_actionTextKey(completed: completed)),
        onPressed: _running ? null : () => Navigator.of(context).pop(),
      ),
    ];
  }

  String _actionTextKey({required bool completed}) {
    if (_running) {
      return 'host.progress.running';
    }

    if (completed) {
      return 'host.progress.viewControlPanel';
    }

    return 'common.close';
  }
}

class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({
    required this.running,
    required this.failed,
    required this.completed,
  });

  final bool running;
  final bool failed;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = failed
        ? Colors.red
        : completed
        ? Colors.green
        : kActiveColor;
    final messageKey = failed
        ? 'host.progress.failed'
        : completed
        ? 'host.progress.completed'
        : 'host.progress.running';

    return Row(
      children: [
        if (running)
          const SizedBox(
            width: 18,
            height: 18,
            child: ProgressRing(strokeWidth: 2),
          )
        else
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            l10n.text(messageKey),
            style: FluentTheme.of(context).typography.bodyLarge?.copyWith(
              color: color,
              fontFamily: FontFamily.battlefrontUI,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressEventRow extends StatelessWidget {
  const _ProgressEventRow({required this.event});

  final HostStartProgressEvent event;

  @override
  Widget build(BuildContext context) {
    final color = switch (event.status) {
      HostStartProgressStatus.running => Colors.white.withValues(alpha: .82),
      HostStartProgressStatus.success => Colors.green,
      HostStartProgressStatus.error => Colors.red,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              _formatTime(event.timestamp),
              style: FluentTheme.of(context).typography.caption?.copyWith(
                color: Colors.white.withValues(alpha: .48),
              ),
            ),
          ),
          Expanded(
            child: Text(
              event.resolve(context),
              style: FluentTheme.of(context).typography.body?.copyWith(
                color: color,
                height: 1.24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime value) {
    return [
      value.hour,
      value.minute,
      value.second,
    ].map((part) => part.toString().padLeft(2, '0')).join(':');
  }
}
