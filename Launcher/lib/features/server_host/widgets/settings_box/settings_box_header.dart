import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:grpc/grpc.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/map_rotation/providers/map_rotation_cubit.dart';
import 'package:kyber_launcher/features/server_host/dialogs/dedicated_host_setup_dialog.dart';
import 'package:kyber_launcher/features/server_host/dialogs/host_start_progress_dialog.dart';
import 'package:kyber_launcher/features/server_host/models/host_start_progress_event.dart';
import 'package:kyber_launcher/features/server_host/providers/host_collection_cubit.dart';
import 'package:kyber_launcher/features/server_host/services/dedicated_host_user_config_service.dart';
import 'package:kyber_launcher/features/server_host/services/external_dedicated_host_service.dart';
import 'package:kyber_launcher/features/server_host/services/server_host_start_service.dart';
import 'package:kyber_launcher/features/server_host/services/server_map_image_upload_service.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/server_settings_box.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_cubit.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';
import 'package:logging/logging.dart';

class SettingsBoxHeader extends StatefulWidget {
  const SettingsBoxHeader({
    required this.onPageChanged,
    required this.selectedPage,
    this.onServerStarted,
    this.lanOnly = false,
    super.key,
  });

  static final _logger = Logger('server_host_settings');

  final void Function(int page) onPageChanged;
  final int selectedPage;
  final VoidCallback? onServerStarted;
  final bool lanOnly;

  @override
  State<SettingsBoxHeader> createState() => _SettingsBoxHeaderState();
}

class _SettingsBoxHeaderState extends State<SettingsBoxHeader> {
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(10).copyWith(left: 10, top: 20, right: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BlocBuilder<ModerationCubit, ModerationServerState>(
            builder: (context, state) {
              return FractionallySizedBox(
                widthFactor: 0.8,
                child: KyberFormInputField(
                  name: 'serverName',
                  initialValue: state.selected ? state.server?.name : null,
                  validator: FormBuilderValidators.compose([
                    FormBuilderValidators.required(),
                    FormBuilderValidators.minLength(3),
                    FormBuilderValidators.maxLength(25),
                  ]),
                  placeholder: l10n.text('host.serverNamePlaceholder'),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          if (widget.lanOnly) ...[
            Text(
              l10n.text('host.lanDedicatedHint'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: FluentTheme.of(context).typography.caption?.copyWith(
                color: Colors.white.withValues(alpha: .78),
                height: 1.22,
              ),
            ),
            const SizedBox(height: 12),
          ] else
            const SizedBox(height: 30),
          Row(
            children: [
              Expanded(
                child: BlocBuilder<ModerationCubit, ModerationServerState>(
                  builder: (context, state) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: KyberButton(
                          text: _buttonText(context, state),
                          onPressed: _starting
                              ? null
                              : () => _openStartDialog(context, state),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 35,
                width: widget.lanOnly ? 180 : 220,
                child: KyberTabBar(
                  tabs: [
                    Text(l10n.text('common.settings')),
                    Text(l10n.text('common.info')),
                  ],
                  onChanged: widget.onPageChanged,
                  selectedIndex: widget.selectedPage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _buttonText(BuildContext context, ModerationServerState state) {
    final l10n = context.l10n;
    if (_starting) {
      return l10n.text('host.startingServer');
    }

    if (state.selected) {
      return l10n.text('host.updateServer');
    }

    if (widget.lanOnly) {
      return l10n.text('host.startDedicatedServerShort');
    }

    return l10n.text('host.startServer');
  }

  Future<void> _openStartDialog(
    BuildContext context,
    ModerationServerState state,
  ) async {
    if (_starting) {
      NotificationService.info(
        message: context.l10n.text('host.progress.alreadyRunning'),
      );
      return;
    }

    if (widget.lanOnly && !await _ensureDedicatedHostConfigured(context)) {
      return;
    }
    if (!mounted || !context.mounted) {
      return;
    }

    setState(() => _starting = true);
    await showKyberDialog<void>(
      context: context,
      barrierDismissible: false,
      dismissWithEsc: false,
      builder: (_) => HostStartProgressDialog(
        titleKey: widget.lanOnly
            ? 'host.progress.dedicatedTitle'
            : 'host.progress.title',
        onStart: (progress) => _executeStart(context, state, progress),
        onConfigure: widget.lanOnly
            ? () => _openDedicatedHostSetup(context)
            : null,
        onCleanup: widget.lanOnly
            ? (progress) => sl
                  .get<ExternalDedicatedHostService>()
                  .cleanupOrphans(onProgress: progress)
            : null,
      ),
    );

    if (mounted) {
      setState(() => _starting = false);
    }
  }

  Future<bool> _ensureDedicatedHostConfigured(BuildContext context) async {
    final service = sl.get<DedicatedHostUserConfigService>();
    if (await service.isLaunchConfigured()) {
      return true;
    }
    if (!context.mounted) {
      return false;
    }

    final configured = await _openDedicatedHostSetup(context);
    if (configured) {
      return service.isLaunchConfigured();
    }

    if (context.mounted) {
      NotificationService.info(
        message: context.l10n.text('settings.dedicatedHost.required'),
      );
    }
    return false;
  }

  Future<bool> _openDedicatedHostSetup(BuildContext context) async {
    if (!context.mounted) {
      return false;
    }

    final configured = await showKyberDialog<bool>(
      context: context,
      builder: (_) => const DedicatedHostSetupDialog(),
    );
    if (configured != true) {
      return false;
    }

    return sl.get<DedicatedHostUserConfigService>().isLaunchConfigured();
  }

  Future<void> _executeStart(
    BuildContext context,
    ModerationServerState state,
    HostStartProgressSink progress,
  ) async {
    final l10n = context.l10n;
    final startService = ServerHostStartService();

    try {
      progress(
        HostStartProgressEvent(messageKey: 'host.progress.validateForm'),
      );
      final form = hostingForm.currentState;
      if (form == null) {
        _progressError(
          progress,
          message: l10n.text('host.progress.formUnavailable'),
        );
        NotificationService.error(
          message: l10n.text('host.progress.formUnavailable'),
        );
        return;
      }

      if (!form.saveAndValidate()) {
        final firstError = form.errors.entries.firstOrNull;
        final field = firstError?.key ?? 'form';
        final message =
            firstError?.value ?? l10n.text('host.progress.formInvalid');
        SettingsBoxHeader._logger.warning(
          'LAN_STAGE[host.ui.validate.failed] '
          'field=$field error=$message',
        );
        _progressError(
          progress,
          message: l10n.text(
            'host.progress.formInvalidWithField',
            params: {'field': field, 'message': message},
          ),
        );
        NotificationService.showNotification(
          title: field,
          message: message,
          severity: InfoBarSeverity.error,
        );
        return;
      }

      progress(
        HostStartProgressEvent(messageKey: 'host.progress.formValidated'),
      );

      final collection = context
          .read<HostCollectionCubit>()
          .state
          .selectedModCollection;
      final mapEntries = List.of(context.read<MapRotationCubit>().state.maps);
      progress(
        HostStartProgressEvent(
          messageKey: 'host.progress.rotationCollected',
          params: {'count': mapEntries.length},
        ),
      );

      final draft = HostStartDraft.fromForm(
        Map<String, Object?>.from(form.value),
        collection: collection,
        mapEntries: mapEntries,
      );

      if (state.selected) {
        await startService.updateExistingServer(
          serverId: state.id,
          draft: draft,
          onProgress: progress,
        );
        NotificationService.showNotification(
          message: l10n.text('host.serverUpdated'),
        );
        return;
      }

      startService.validateDraft(draft, onProgress: progress);
      if (draft.onlineMode) {
        progress(
          HostStartProgressEvent(messageKey: 'host.progress.uploadHashes'),
        );
        await ServerMapImageUploadService().uploadMissingHashes(
          context,
          collection: collection,
          entries: mapEntries,
        );
        progress(
          HostStartProgressEvent(messageKey: 'host.progress.uploadHashesDone'),
        );
        if (!mounted || !context.mounted) {
          return;
        }
      }

      await startService.startNewServer(
        context,
        draft,
        onProgress: progress,
        validate: false,
      );
      if (widget.lanOnly) {
        widget.onServerStarted?.call();
      }
    } on HostStartRejectedException catch (e) {
      final message = e.messageKey == null
          ? e.fallbackMessage ?? l10n.text('host.unexpectedStartServerError')
          : l10n.text(e.messageKey!, params: e.params);
      _progressError(progress, message: message);
      NotificationService.error(message: message);
    } on GrpcError catch (e) {
      final message = l10n.text(
        'host.failedToStartServer',
        params: {'message': e.message ?? ''},
      );
      SettingsBoxHeader._logger.severe(
        'LAN_STAGE[host.ui.start.error.grpc] message=${e.message}',
      );
      _progressError(progress, message: message);
      NotificationService.error(message: message);
    } on Object catch (e, stack) {
      SettingsBoxHeader._logger.severe(
        'LAN_STAGE[host.ui.start.error] error=$e',
        e,
        stack,
      );
      final message = l10n.text(
        'host.failedToStartServer',
        params: {'message': e},
      );
      _progressError(progress, message: message);
      NotificationService.error(message: message);
    }
  }

  void _progressError(
    HostStartProgressSink progress, {
    required String message,
  }) {
    progress(
      HostStartProgressEvent(
        message: message,
        status: HostStartProgressStatus.error,
      ),
    );
  }
}

extension _FirstOrNullEntry<K, V> on Iterable<MapEntry<K, V>> {
  MapEntry<K, V>? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }

    return iterator.current;
  }
}
