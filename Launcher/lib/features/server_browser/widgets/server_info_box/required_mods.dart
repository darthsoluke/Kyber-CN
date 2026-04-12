import 'package:background_downloader/background_downloader.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/features/download_manager/models/download_state.dart';
import 'package:kyber_launcher/features/download_manager/providers/download_manager_cubit.dart';
import 'package:kyber_launcher/features/mods/helper/mod_helper.dart';
import 'package:kyber_launcher/features/mods/services/mod_service.dart';
import 'package:kyber_launcher/features/server_browser/providers/server_browser_cubit.dart';
import 'package:kyber_launcher/features/server_browser/widgets/server_mod_tile.dart';
import 'package:kyber_launcher/features/tutorial/models/tutorials/server_browser_tutorial.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class ServerRequiredMods extends StatefulWidget {
  const ServerRequiredMods({required this.server, super.key});

  final Server server;

  @override
  State<ServerRequiredMods> createState() => _ServerRequiredModsState();
}

class _ServerRequiredModsState extends State<ServerRequiredMods> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ServerBrowserCubit, ServerBrowserState>(
      builder: (context, state) {
        if (widget.server.mods.isEmpty) {
          return ClipRRect(
            borderRadius: const .vertical(
              bottom: .circular(kDefaultOuterBorderRadius),
            ),
            child: BackgroundBlur(
              child: Container(
                height: 40,
                decoration: const BoxDecoration(
                  border: kDefaultAllBorder,
                  borderRadius: .vertical(
                    bottom: .circular(kDefaultOuterBorderRadius),
                  ),
                ),
                child: Align(
                  child: Text(
                    'No mods required'.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1,
                      fontFamily: FontFamily.battlefrontUI,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return ListenableBuilder(
          key: ServerBrowserTutorial.serverInfoModsKey,
          listenable: sl.get<ModService>(),
          builder: (_, __) => BlocBuilder<DownloadCubit, DownloadState>(
            buildWhen: (previous, current) {
              final prevDownload = previous is DownloadLoaded
                  ? previous.currentDownload
                  : null;
              final currDownload = current is DownloadLoaded
                  ? current.currentDownload
                  : null;
              return prevDownload != currDownload;
            },
            builder: (context, state) {
              return ClipRRect(
                borderRadius: const .vertical(
                  bottom: .circular(kDefaultOuterBorderRadius),
                ),
                child: BackgroundBlur(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: const BoxDecoration(
                              borderRadius: .vertical(
                                bottom: .circular(
                                  kDefaultOuterBorderRadius,
                                ),
                              ),
                              border: Border(
                                bottom: kDefaultBorder,
                                left: kDefaultBorder,
                                right: kDefaultBorder,
                              ),
                            ),
                          ),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: const .vertical(
                          bottom: .circular(kDefaultOuterBorderRadius + 4),
                        ),
                        child: RepaintBoundary(
                          key: const Key('server_list'),
                          child: KyberList(
                            colorOpacity: 0,
                            shrinkWrap: true,
                            blur: false,
                            activeIndex: -1,
                            itemPadding: .zero,
                            physics: const ScrollPhysics(),
                            itemBuilder: (context, index) {
                              final mod = widget.server.mods[index];
                              return BlocBuilder<DownloadCubit, DownloadState>(
                                buildWhen: (previous, current) {
                                  final prevDownload =
                                      previous is DownloadLoaded
                                      ? previous.currentDownload
                                      : null;
                                  final currDownload = current is DownloadLoaded
                                      ? current.currentDownload
                                      : null;
                                  return prevDownload != currDownload;
                                },
                                builder: (context, state) {
                                  final currentDownload =
                                      state is DownloadLoaded
                                      ? state.currentDownload
                                      : null;

                                  return RepaintBoundary(
                                    child: _ModEntry(
                                      server: widget.server,
                                      mod: mod,
                                      activeDownload: currentDownload,
                                    ),
                                  );
                                },
                              );
                            },
                            itemCount: widget.server.mods.length,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: const BoxDecoration(
                              borderRadius: .vertical(
                                bottom: .circular(
                                  kDefaultOuterBorderRadius,
                                ),
                              ),
                              border: Border(bottom: kDefaultBorder),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ModEntry extends StatefulWidget {
  const _ModEntry({
    required this.server,
    required this.mod,
    this.activeDownload,
  });

  final Server server;
  final ServerMod mod;
  final TaskRecord? activeDownload;

  @override
  State<_ModEntry> createState() => _ModEntryState();
}

class _ModEntryState extends State<_ModEntry> {
  ServerMod? currentInstalling;

  @override
  void initState() {
    if (widget.activeDownload != null) {
      try {
        currentInstalling = ServerMod.fromJson(
          widget.activeDownload!.task.metaData,
        );
      } catch (e) {}
    }
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _ModEntry oldWidget) {
    if (widget.activeDownload != null) {
      try {
        currentInstalling = ServerMod.fromJson(
          widget.activeDownload!.task.metaData,
        );
      } catch (_) {
        currentInstalling = null;
      }
    } else {
      currentInstalling = null;
    }

    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    final downloading =
        currentInstalling?.name == widget.mod.name &&
        currentInstalling?.version == widget.mod.version;

    final child = ServerModTile(mod: widget.mod, downloading: downloading);

    if (!downloading) {
      return child;
    }

    return BlocBuilder<DownloadCubit, DownloadState>(
      builder: (context, state) {
        final progressUpdate = state is DownloadLoaded
            ? state.progressUpdate
            : null;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            if (downloading)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 7,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          kActiveColor,
                          Colors.transparent,
                        ],
                        stops: [
                          progressUpdate?.progress ?? 1 / 100,
                          progressUpdate?.progress ?? 1 / 100,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
