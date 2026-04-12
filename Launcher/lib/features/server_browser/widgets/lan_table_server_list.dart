import 'package:collection/collection.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_fadein/flutter_fadein.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/features/kyber/models/maps.dart';
import 'package:kyber_launcher/features/kyber/models/mode.dart';
import 'package:kyber_launcher/features/kyber/models/modes.dart';
import 'package:kyber_launcher/features/server_browser/models/server_filter.dart';
import 'package:kyber_launcher/features/server_browser/models/server_list_state.dart';
import 'package:kyber_launcher/features/server_browser/providers/lan_server_list_cubit.dart';
import 'package:kyber_launcher/features/server_browser/widgets/server_list/entry.dart';
import 'package:kyber_launcher/features/server_browser/widgets/server_list/server_list_header.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class LanTableServerList extends StatefulWidget {
  const LanTableServerList({super.key});

  @override
  State<LanTableServerList> createState() => _LanTableServerListState();
}

class _LanTableServerListState extends State<LanTableServerList> {
  int? hoverIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const ServerListHeader(),
        Expanded(
          child: FadeIn(
            curve: Curves.easeOut,
            duration: const Duration(milliseconds: 100),
            child: BlocBuilder<LanServerListCubit, ServerListState>(
              builder: (context, state) {
                state as ServerListLoaded;
                final servers = state.servers;

                if (servers.isEmpty) {
                  return Center(
                    child: Text(
                      'No LAN servers found',
                      style: FluentTheme.of(context).typography.subtitle
                          ?.copyWith(fontFamily: FontFamily.battlefrontUI),
                    ),
                  );
                }

                return FadeIn(
                  duration: const Duration(milliseconds: 150),
                  child: SuperListView.builder(
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return const SizedBox.shrink();
                      }

                      final server = servers[index - 1] as Server;
                      final mode = modes
                              .where(
                                (element) =>
                                    element.mode == server.levelSetup.mode,
                              )
                              .firstOrNull ??
                          Mode.customMode();
                      final map = mode.maps.isEmpty
                          ? maps.first
                          : maps.firstWhereOrNull(
                                (element) =>
                                    element['map'] == server.levelSetup.map,
                              ) ??
                              maps.first;

                      return ServerListEntry(
                        server: server,
                        index: index - 1,
                        isLast: index == servers.length,
                        hoveredIndex: hoverIndex ?? -1,
                        onHover: (value) {
                          setState(() => hoverIndex = value ? index : null);
                        },
                        mode: mode,
                        map: map,
                      );
                    },
                    itemCount: servers.isEmpty ? 0 : servers.length + 1,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
