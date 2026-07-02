import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/features/maxima/providers/maxima_cubit.dart';
import 'package:kyber_launcher/features/maxima/services/maxima_instance_service.dart';
import 'package:kyber_launcher/features/server_browser/dialogs/sakura_frp_setup_dialog.dart';
import 'package:kyber_launcher/features/server_host/dialogs/dedicated_host_setup_dialog.dart';
import 'package:kyber_launcher/features/server_host/services/dedicated_host_user_config_service.dart';
import 'package:kyber_launcher/features/server_host/services/dedicated_server_network_service.dart';
import 'package:kyber_launcher/features/server_host/services/external_dedicated_host_service.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/server_settings_box.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_cubit.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class ServerSettings extends StatelessWidget {
  const ServerSettings({super.key, this.lanOnly = false});

  final bool lanOnly;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SuperListView(
      children: [
        const _HostEnvironmentSettings(),
        if (lanOnly) const BfiiHostControlPanel(),
        KyberSectionDropdown(
          initialExpanded: true,
          title: l10n.text('host.server.section'),
          child: KyberTable(
            itemStyle: const TextStyle(fontSize: 17),
            items: [
              KyberTableItem.custom(
                title: l10n.text('host.authMode'),
                builder: (hovered) {
                  if (lanOnly) {
                    return FormBuilderField<bool>(
                      name: 'onlineMode',
                      initialValue: false,
                      builder: (_) => Text(
                        l10n.text('host.dedicatedLanMode'),
                        style: const TextStyle(fontSize: 17),
                      ),
                    );
                  }

                  return FormBuilderField<bool>(
                    name: 'onlineMode',
                    builder: (field) {
                      final value = field.value ?? true;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => field.didChange(!value),
                        child: KyberTableSwitch(
                          hover: hovered,
                          value: value,
                          disabledText: l10n.text('host.offline'),
                          enabledText: l10n.text('host.online'),
                          onChanged: (value) => field.didChange(value),
                        ),
                      );
                    },
                  );
                },
              ),
              KyberTableItem.custom(
                title: l10n.text('host.port'),
                builder: (hovered) {
                  return SizedBox(
                    width: 140,
                    child: KyberFormInputField(
                      name: 'serverPort',
                      placeholder: l10n.text('host.portPlaceholder'),
                      validator: (value) {
                        final port = int.tryParse((value ?? '').toString());
                        if (port == null || port <= 0 || port > 65535) {
                          return l10n.text('host.invalidPort');
                        }

                        return null;
                      },
                    ),
                  );
                },
              ),
              KyberTableItem.custom(
                title: l10n.text('host.maxPlayers'),
                builder: (hovered) {
                  return FormBuilderField<int>(
                    name: 'maxPlayers',
                    builder: (field) {
                      return KyberTableSlider(
                        hover: hovered,
                        min: 2,
                        max: 64,
                        value: field.value!,
                        onChanged: (value) {
                          field.didChange(value);
                          final maxPlayersField = hostingForm
                              .currentState!
                              .fields['maxSpectators']!;
                          final maxPlayers = maxPlayersField.value as int;
                          if (maxPlayers + value > 64) {
                            hostingForm.currentState!.fields['maxSpectators']!
                                .setValue(64 - value);
                          }
                        },
                      );
                    },
                  );
                },
              ),
              KyberTableItem.custom(
                title: l10n.text('host.maxSpectators'),
                builder: (hovered) {
                  return FormBuilderField<int>(
                    name: 'maxSpectators',
                    builder: (field) {
                      return KyberTableSlider(
                        hover: hovered,
                        min: 0,
                        max: 62,
                        value: field.value!,
                        onChanged: (value) {
                          field.didChange(value);
                          final maxPlayersField =
                              hostingForm.currentState!.fields['maxPlayers']!;
                          final maxPlayers = maxPlayersField.value as int;
                          if (maxPlayers + value > 64) {
                            hostingForm.currentState!.fields['maxPlayers']!
                                .setValue(64 - value);
                          }
                        },
                      );
                    },
                  );
                },
              ),
              KyberTableItem.switchButton(
                title: l10n.text('host.proximityChat'),
                value: true,
                onChange: (value) async {
                  NotificationService.notImplemented();
                },
              ),
            ],
          ),
        ),
        KyberSectionDropdown(
          initialExpanded: true,
          title: l10n.text('host.privacy.section'),
          child: KyberTable(
            itemStyle: const TextStyle(fontSize: 17),
            items: [
              KyberTableItem.custom(
                title: l10n.text('host.password'),
                builder: (hovered) {
                  return KyberFormInputField(
                    name: 'password',
                    isSensitive: true,
                    placeholder: l10n.text('host.passwordPlaceholder'),
                    validator: FormBuilderValidators.compose(
                      [
                        FormBuilderValidators.maxLength(
                          25,
                          checkNullOrEmpty: false,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HostEnvironmentSettings extends StatefulWidget {
  const _HostEnvironmentSettings();

  @override
  State<_HostEnvironmentSettings> createState() =>
      _HostEnvironmentSettingsState();
}

class _HostEnvironmentSettingsState extends State<_HostEnvironmentSettings> {
  Future<void> _requestMaximaLogin(BuildContext context) async {
    try {
      await context.read<MaximaCubit>().requestLogin();
      if (!context.mounted) {
        return;
      }

      NotificationService.success(
        message: context.l10n.text('host.environmentNetwork.maximaLoginDone'),
      );
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }

      NotificationService.error(
        title: context.l10n.text('host.environmentNetwork.maximaLoginFailed'),
        message: error.toString(),
      );
    }
  }

  Future<void> _openDedicatedHostSetup(BuildContext context) async {
    await showKyberDialog<bool>(
      context: context,
      builder: (_) => const DedicatedHostSetupDialog(),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openSakuraFrpSetup(BuildContext context) async {
    await showKyberDialog<bool>(
      context: context,
      builder: (_) => const SakuraFrpSetupDialog(),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final configService = sl.get<DedicatedHostUserConfigService>();

    return KyberSectionDropdown(
      initialExpanded: true,
      title: l10n.text('host.environmentNetwork.section'),
      child: KyberTable(
        itemStyle: const TextStyle(fontSize: 17),
        items: [
          KyberTableItem.custom(
            title: l10n.text('host.environmentNetwork.maximaAccount'),
            builder: (_) => BlocBuilder<MaximaCubit, MaximaState>(
              builder: (context, state) {
                final busy =
                    state.status == MaximaStatus.loading ||
                    state.status == MaximaStatus.starting;
                final status = _maximaStatusText(context, state);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        status,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: state.loggedIn ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    KyberButton(
                      text: busy
                          ? l10n.text(
                              'host.environmentNetwork.maximaLoggingIn',
                            )
                          : state.loggedIn
                          ? l10n.text('host.environmentNetwork.maximaRelogin')
                          : l10n.text('host.environmentNetwork.maximaLogin'),
                      onPressed: busy
                          ? null
                          : () => _requestMaximaLogin(context),
                    ),
                  ],
                );
              },
            ),
          ),
          KyberTableItem.button(
            title: l10n.text('host.environmentNetwork.dedicatedHost'),
            text: l10n.text('common.settings'),
            onClick: () => _openDedicatedHostSetup(context),
          ),
          KyberTableItem.custom(
            title: l10n.text('host.environmentNetwork.dedicatedStatus'),
            builder: (_) => FutureBuilder<List<String>>(
              future: configService.missingLaunchRequirements(),
              builder: (context, snapshot) {
                final missing = snapshot.data ?? const <String>[];
                final ready =
                    snapshot.connectionState == ConnectionState.done &&
                    missing.isEmpty;
                return Text(
                  ready
                      ? l10n.text('host.environmentNetwork.ready')
                      : l10n.text('host.environmentNetwork.needsSetup'),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: ready ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ),
          KyberTableItem.button(
            title: l10n.text('host.environmentNetwork.sakuraFrp'),
            text: l10n.text('common.settings'),
            onClick: () => _openSakuraFrpSetup(context),
          ),
          KyberTableItem.custom(
            title: l10n.text('host.environmentNetwork.sakuraFrpStatus'),
            builder: (_) => Text(
              _sakuraFrpStatus(context),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Preferences.sakuraFrp.enabled
                    ? Colors.green
                    : Colors.orange,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _maximaStatusText(BuildContext context, MaximaState state) {
    final l10n = context.l10n;
    if (state.loggedIn) {
      return l10n.text(
        'host.environmentNetwork.maximaLoggedIn',
        params: {
          'name':
              state.servicePlayer?.displayName ??
              state.servicePlayer?.uniqueName ??
              '',
        },
      );
    }

    if (state.status == MaximaStatus.loading ||
        state.status == MaximaStatus.starting) {
      return l10n.text('host.environmentNetwork.maximaLoggingIn');
    }

    if (state.status == MaximaStatus.error) {
      return l10n.text('host.environmentNetwork.maximaError');
    }

    return l10n.text('host.environmentNetwork.maximaNotLoggedIn');
  }

  String _sakuraFrpStatus(BuildContext context) {
    final l10n = context.l10n;
    if (!Preferences.sakuraFrp.enabled) {
      return l10n.text('host.environmentNetwork.disabled');
    }

    final endpointCount =
        _endpointCount(
          Preferences.sakuraFrp.manualEndpoints,
        ) +
        _endpointCount(Preferences.sakuraFrp.cachedEndpoints);
    if (endpointCount == 0 && Preferences.sakuraFrp.apiToken.trim().isEmpty) {
      return l10n.text('host.environmentNetwork.needsSetup');
    }

    return l10n.text(
      'host.environmentNetwork.sakuraFrpReady',
      params: {'count': endpointCount},
    );
  }

  int _endpointCount(String value) {
    return value
        .split(RegExp(r'[\r\n]+'))
        .where((line) => line.trim().isNotEmpty && !line.trim().startsWith('#'))
        .length;
  }
}

class BfiiHostControlPanel extends StatelessWidget {
  const BfiiHostControlPanel({
    this.showOpenPanelButton = true,
    super.key,
  });

  final bool showOpenPanelButton;

  @override
  Widget build(BuildContext context) {
    final instanceService = sl.get<MaximaInstanceService>();
    final externalService = sl.get<ExternalDedicatedHostService>();

    return ListenableBuilder(
      listenable: externalService,
      builder: (context, _) {
        final externalState = externalService.state;
        if (externalState.status != ExternalDedicatedHostStatus.idle) {
          return _ExternalBfiiHostControlPanel(
            service: externalService,
            state: externalState,
            showOpenPanelButton: showOpenPanelButton,
          );
        }

        return ListenableBuilder(
          listenable: instanceService,
          builder: (context, _) {
            final l10n = context.l10n;
            final server = instanceService.bfiiHostInstance;
            if (server == null) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .14),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.text('host.dedicatedControl.title'),
                      style: FluentTheme.of(context).typography.bodyStrong,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.text(
                        'host.dedicatedControl.status',
                        params: {
                          'pid': server.pid,
                          'mods': server.gameplayMods.length,
                        },
                      ),
                      style: FluentTheme.of(context).typography.caption,
                    ),
                    const SizedBox(height: 8),
                    _DedicatedServerMetadata(server: server),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (showOpenPanelButton) ...[
                          KyberButton(
                            text: l10n.text('host.dedicatedControl.openPanel'),
                            onPressed: () async {
                              try {
                                await context
                                    .read<ModerationCubit>()
                                    .selectServer();
                              } on Object catch (e) {
                                NotificationService.error(message: '$e');
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        KyberButton(
                          text: l10n.text('host.dedicatedControl.stop'),
                          onPressed: () async {
                            try {
                              await instanceService.stopBfiiHostServer();
                              if (context.mounted) {
                                context.read<ModerationCubit>().unloadServer();
                              }
                              NotificationService.info(
                                message: l10n.text(
                                  'host.dedicatedControl.stopped',
                                ),
                              );
                            } on Object catch (e) {
                              NotificationService.error(message: '$e');
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ExternalBfiiHostControlPanel extends StatelessWidget {
  const _ExternalBfiiHostControlPanel({
    required this.service,
    required this.state,
    required this.showOpenPanelButton,
  });

  final ExternalDedicatedHostService service;
  final ExternalDedicatedHostState state;
  final bool showOpenPanelButton;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canStop =
        state.status != ExternalDedicatedHostStatus.starting &&
        state.status != ExternalDedicatedHostStatus.stopping;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .28),
          border: Border.all(
            color: _statusColor().withValues(alpha: .38),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.text('host.dedicatedControl.title'),
              style: FluentTheme.of(context).typography.bodyStrong,
            ),
            const SizedBox(height: 8),
            Text(
              _statusText(context),
              style: FluentTheme.of(context).typography.caption?.copyWith(
                color: _statusColor(),
              ),
            ),
            const SizedBox(height: 8),
            _ExternalDedicatedServerMetadata(state: state),
            const SizedBox(height: 10),
            _ExternalHostLogs(logs: state.logs),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (showOpenPanelButton &&
                    state.status == ExternalDedicatedHostStatus.running) ...[
                  KyberButton(
                    text: l10n.text('host.dedicatedControl.openPanel'),
                    onPressed: () async {
                      try {
                        await context.read<ModerationCubit>().selectServer();
                      } on Object catch (e) {
                        NotificationService.error(message: '$e');
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                KyberButton(
                  text: l10n.text('host.dedicatedControl.stop'),
                  onPressed: canStop
                      ? () async {
                          try {
                            await service.stop();
                            if (context.mounted) {
                              context.read<ModerationCubit>().unloadServer();
                            }
                            NotificationService.info(
                              message: l10n.text(
                                'host.dedicatedControl.stopped',
                              ),
                            );
                          } on Object catch (e) {
                            NotificationService.error(message: '$e');
                          }
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor() {
    return switch (state.status) {
      ExternalDedicatedHostStatus.running => Colors.green,
      ExternalDedicatedHostStatus.failed => Colors.red,
      ExternalDedicatedHostStatus.stopping => Colors.orange,
      ExternalDedicatedHostStatus.starting => Colors.yellow,
      ExternalDedicatedHostStatus.idle => Colors.white,
    };
  }

  String _statusText(BuildContext context) {
    final l10n = context.l10n;
    final status = l10n.text(
      switch (state.status) {
        ExternalDedicatedHostStatus.running => 'host.dedicatedControl.running',
        ExternalDedicatedHostStatus.failed => 'host.dedicatedControl.failed',
        ExternalDedicatedHostStatus.stopping =>
          'host.dedicatedControl.stopping',
        ExternalDedicatedHostStatus.starting =>
          'host.dedicatedControl.starting',
        ExternalDedicatedHostStatus.idle => 'host.dedicatedControl.idle',
      },
    );

    return l10n.text(
      'host.dedicatedControl.externalStatus',
      params: {
        'status': status,
        'pid': state.pid ?? '-',
        'logs': state.logs.length,
      },
    );
  }
}

class _ExternalDedicatedServerMetadata extends StatelessWidget {
  const _ExternalDedicatedServerMetadata({required this.state});

  final ExternalDedicatedHostState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final port = state.port ?? 25200;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.text(
            'host.dedicatedControl.server',
            params: {
              'name': state.serverName ?? '-',
              'port': port,
            },
          ),
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.text('host.dedicatedControl.joinAddresses'),
          style: FluentTheme.of(context).typography.bodyStrong,
        ),
        const SizedBox(height: 6),
        FutureBuilder<List<DedicatedServerJoinAddress>>(
          future: const DedicatedServerNetworkService().getJoinAddresses(
            port: port,
          ),
          builder: (context, snapshot) {
            final addresses = snapshot.data ?? const [];
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 18,
                width: 18,
                child: ProgressRing(strokeWidth: 2),
              );
            }

            if (addresses.isEmpty) {
              return Text(
                l10n.text('host.dedicatedControl.noJoinAddress'),
                style: FluentTheme.of(context).typography.caption,
              );
            }

            return Column(
              children: [
                for (final address in addresses.take(4))
                  _JoinAddressRow(address: address),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ExternalHostLogs extends StatelessWidget {
  const _ExternalHostLogs({required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final visibleLogs = logs.length > 8 ? logs.sublist(logs.length - 8) : logs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.text('host.dedicatedControl.logs'),
          style: FluentTheme.of(context).typography.bodyStrong,
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 120),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .32),
            border: Border.all(
              color: Colors.white.withValues(alpha: .12),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: SelectableText(
            visibleLogs.isEmpty ? '-' : visibleLogs.join('\n'),
            style: FluentTheme.of(context).typography.caption?.copyWith(
              color: Colors.white.withValues(alpha: .72),
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _DedicatedServerMetadata extends StatelessWidget {
  const _DedicatedServerMetadata({required this.server});

  final BfiiHostInstance server;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final metadata = server.serverMetadata;
    final port = metadata?.port ?? 25200;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (metadata != null) ...[
          Text(
            l10n.text(
              'host.dedicatedControl.server',
              params: {
                'name': metadata.name,
                'port': metadata.port,
              },
            ),
            style: FluentTheme.of(context).typography.caption,
          ),
          if (metadata.map != null && metadata.mode != null)
            Text(
              '${metadata.map} / ${metadata.mode}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentTheme.of(context).typography.caption?.copyWith(
                color: Colors.white.withValues(alpha: .62),
              ),
            ),
          const SizedBox(height: 8),
        ],
        Text(
          l10n.text('host.dedicatedControl.joinAddresses'),
          style: FluentTheme.of(context).typography.bodyStrong,
        ),
        const SizedBox(height: 6),
        FutureBuilder<List<DedicatedServerJoinAddress>>(
          future: const DedicatedServerNetworkService().getJoinAddresses(
            port: port,
          ),
          builder: (context, snapshot) {
            final addresses = snapshot.data ?? const [];
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 18,
                width: 18,
                child: ProgressRing(strokeWidth: 2),
              );
            }

            if (addresses.isEmpty) {
              return Text(
                l10n.text('host.dedicatedControl.noJoinAddress'),
                style: FluentTheme.of(context).typography.caption,
              );
            }

            return Column(
              children: [
                for (final address in addresses.take(4))
                  _JoinAddressRow(address: address),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _JoinAddressRow extends StatelessWidget {
  const _JoinAddressRow({required this.address});

  final DedicatedServerJoinAddress address;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${address.endpoint} (${address.interfaceName})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentTheme.of(context).typography.caption,
            ),
          ),
          const SizedBox(width: 8),
          KyberButton(
            text: l10n.text('common.copy'),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: address.endpoint),
              );
              NotificationService.info(
                message: l10n.text('common.copiedToClipboard'),
              );
            },
          ),
        ],
      ),
    );
  }
}
