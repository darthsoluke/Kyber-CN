import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as mt;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/background_image.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/ingame_sub_pages/ingame_actions.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/ingame_sub_pages/ingame_players.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/ingame_sub_pages/ingame_settings.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/settings/server_settings.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/settings_box_header.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_cubit.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

final hostingForm = GlobalKey<FormBuilderState>();

class ServerSettingsBox extends StatefulWidget {
  const ServerSettingsBox({super.key, this.lanOnly = false});

  final bool lanOnly;

  @override
  State<ServerSettingsBox> createState() => _ServerSettingsBoxState();
}

class _ServerSettingsBoxState extends State<ServerSettingsBox> {
  int selectedPage = 0;

  void _showSettingsPage() {
    if (selectedPage == 0) {
      return;
    }

    setState(() => selectedPage = 0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocListener<ModerationCubit, ModerationServerState>(
      listenWhen: (previous, current) =>
          previous.localControl != current.localControl ||
          previous.selected && !current.selected,
      listener: (context, state) => _showSettingsPage(),
      child: FormBuilder(
        key: hostingForm,
        initialValue: {
          'serverName': Preferences.hostServer.name,
          'description': Preferences.hostServer.description,
          'password': Preferences.hostServer.password,
          'serverPort': Preferences.hostServer.port.toString(),
          'maxPlayers': Preferences.hostServer.maxPlayers,
          'maxSpectators': Preferences.hostServer.maxSpectators,
          'onlineMode': !widget.lanOnly && Preferences.hostServer.onlineMode,
        },
        onChanged: () async {
          final state = context.read<ModerationCubit>().state;
          if (!state.selected && state.id == null) {
            Preferences.hostServer.name =
                hostingForm.currentState?.fields['serverName']?.value as String;
            Preferences.hostServer.description =
                (hostingForm.currentState?.fields['description']?.value ?? '')
                    as String;
            Preferences.hostServer.password =
                (hostingForm.currentState?.fields['password']?.value ?? '')
                    as String;
            final parsedPort = int.tryParse(
              (hostingForm.currentState?.fields['serverPort']?.value ?? '')
                  .toString(),
            );
            if (parsedPort != null && parsedPort > 0 && parsedPort <= 65535) {
              Preferences.hostServer.port = parsedPort;
            }
            Preferences.hostServer.maxPlayers =
                (hostingForm.currentState?.fields['maxPlayers']?.value ?? 40)
                    as int;
            Preferences.hostServer.maxSpectators =
                (hostingForm.currentState?.fields['maxSpectators']?.value ?? 0)
                    as int;
            Preferences.hostServer.onlineMode =
                !widget.lanOnly &&
                ((hostingForm.currentState?.fields['onlineMode']?.value ?? true)
                    as bool);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: widget.lanOnly ? 220 : 180,
              child: Panel(
                background: const HostingBackgroundImage(),
                child: SettingsBoxHeader(
                  lanOnly: widget.lanOnly,
                  selectedPage: selectedPage,
                  onPageChanged: (page) => setState(() => selectedPage = page),
                  onServerStarted: _showSettingsPage,
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(kDefaultOuterBorderRadius),
                ),
                child: BackgroundBlur(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(
                                kDefaultOuterBorderRadius,
                              ),
                            ),
                            color: Colors.black.withValues(alpha: .3),
                            border: const Border(
                              left: kDefaultBorder,
                              right: kDefaultBorder,
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child:
                            BlocBuilder<ModerationCubit, ModerationServerState>(
                              builder: (context, state) {
                                if (state.localControl) {
                                  return const _RunningServerControlCenter();
                                }

                                if (selectedPage == 1) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        child: Text(
                                          l10n.text('host.description'),
                                          style: const TextStyle(
                                            fontFamily:
                                                FontFamily.battlefrontUI,
                                            fontSize: 16,
                                            color: kInactiveColor,
                                          ),
                                        ),
                                      ),
                                      const CardSection(),
                                      SizedBox(
                                        height: 300,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                          ),
                                          child: FormBuilderTextField(
                                            decoration: mt.InputDecoration(
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 14,
                                                  ),
                                              hintText: l10n.text(
                                                'host.descriptionPlaceholder',
                                              ),
                                              border: mt.InputBorder.none,
                                              hintStyle: const TextStyle(
                                                fontFamily:
                                                    FontFamily.battlefrontUI,
                                                fontSize: 16,
                                                color: decoColor,
                                              ),
                                            ),
                                            style: const mt.TextStyle(
                                              fontFamily:
                                                  FontFamily.battlefrontUI,
                                              fontSize: 16,
                                              color: kWhiteColor,
                                            ),
                                            name: 'description',
                                            expands: true,
                                            maxLines: null,
                                          ),
                                        ),
                                      ),
                                      const CardSection(),
                                    ],
                                  );
                                }

                                return ServerSettings(lanOnly: widget.lanOnly);
                              },
                            ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: const BoxDecoration(
                              borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(
                                  kDefaultOuterBorderRadius,
                                ),
                              ),
                              border: Border(
                                bottom: kDefaultBorder,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunningServerControlCenter extends StatelessWidget {
  const _RunningServerControlCenter();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SuperListView(
      children: [
        const BfiiHostControlPanel(showOpenPanelButton: false),
        KyberSectionDropdown(
          initialExpanded: true,
          title: l10n.text('host.autoplayers'),
          child: const IngameSettings(),
        ),
        KyberSectionDropdown(
          initialExpanded: true,
          title: l10n.text('host.playersAppliesOnSpawn'),
          child: const IngamePlayers(),
        ),
        KyberSectionDropdown(
          initialExpanded: true,
          title: l10n.text('host.ingameActions'),
          child: const IngameActions(),
        ),
      ],
    );
  }
}
