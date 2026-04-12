import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/features/mods/helper/mod_helper.dart';
import 'package:kyber_launcher/features/mods/services/mod_service.dart';
import 'package:kyber_launcher/features/server_browser/helpers/server_browser_helper.dart';
import 'package:kyber_launcher/features/server_browser/models/server_filter.dart';
import 'package:kyber_launcher/features/server_browser/providers/server_browser_cubit.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class ServerButtonRow extends StatelessWidget {
  const ServerButtonRow({
    super.key,
    this.server,
    this.onServerSelected,
    this.onClose,
    this.onPageChanged,
    this.selectedIndex = 0,
    this.hasModsInstalled = false,
  });

  final bool hasModsInstalled;
  final Server? server;
  final VoidCallback? onServerSelected;
  final void Function(int page)? onPageChanged;
  final int selectedIndex;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final server =
        this.server ??
        (context.read<ServerBrowserCubit>().state.selectedServer! is ServerGroup
            ? (context.read<ServerBrowserCubit>().state.selectedServer!
                      as ServerGroup)
                  .getPreferredServer()
            : context.read<ServerBrowserCubit>().state.selectedServer!
                  as Server);
    final state = onServerSelected != null
        ? null
        : context.watch<ServerBrowserCubit>().state;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ListenableBuilder(
          listenable: sl.get<ModService>(),
          builder: (_, __) {
            final installed = server.mods.every(
              (m) => ModHelper.isInstalled(m.name, m.version),
            );
            var disabled = false;
            if (onServerSelected == null && !installed) {
              disabled = !ServerBrowserHelper.canJoinServer(
                context,
                server: server,
                ignoreInstalled: true,
              );
            }

            return KyberButton(
              onPressed:
                  onServerSelected ??
                  (!disabled
                      ? () async {
                          context.read<ServerBrowserCubit>().joinServer();
                        }
                      : null),
              text: onServerSelected != null
                  ? l10n.text('host.moderate')
                  : installed
                  ? l10n.text('serverBrowser.playNow')
                  : l10n.text('serverBrowser.downloadMods'),
            );
          },
        ),
        if (onPageChanged != null &&
            (server.description.isNotEmpty ||
                state?.selectedServer is ServerGroup))
          SizedBox(
            height: 35,
            width: 200,
            child: KyberTabBar(
              tabs: [
                Text(l10n.text('common.mods')),
                if (server.description.isNotEmpty)
                  Text(l10n.text('common.info')),
                if (context.read<ServerBrowserCubit>().state.selectedServer
                    is ServerGroup)
                  Text(l10n.text('serverBrowser.tab.servers')),
              ],
              onChanged: onPageChanged ?? (index) {},
              selectedIndex: selectedIndex,
            ),
          ),
      ],
    );
  }
}
