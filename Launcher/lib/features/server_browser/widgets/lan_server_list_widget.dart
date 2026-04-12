import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/features/server_browser/models/server_list_state.dart';
import 'package:kyber_launcher/features/server_browser/providers/lan_server_list_cubit.dart';
import 'package:kyber_launcher/features/server_browser/widgets/lan_table_server_list.dart';
import 'package:kyber_launcher/features/server_browser/widgets/server_list/server_list_header.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class LanServerListWidget extends StatefulWidget {
  const LanServerListWidget({super.key});

  @override
  State<LanServerListWidget> createState() => _LanServerListWidgetState();
}

class _LanServerListWidgetState extends State<LanServerListWidget> {
  @override
  void initState() {
    Timer.run(context.read<LanServerListCubit>().checkUpdate);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LanServerListCubit, ServerListState>(
      builder: (context, state) {
        if (state is ServerListLoading) {
          return const Column(
            children: [
              ServerListHeader(),
              Expanded(child: Center(child: ProgressBar())),
            ],
          );
        }

        if (state is ServerListLoaded) {
          return const RepaintBoundary(child: LanTableServerList());
        }

        if (state is ServerListError) {
          return Padding(
            padding: const EdgeInsets.only(top: 15),
            child: CustomBorder(
              clipper: KyberEventsCustomBorderClipper(),
              painter: KyberEventsCustomBorderPainter(),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.message,
                    style: FluentTheme.of(context).typography.subtitle
                        ?.copyWith(fontFamily: FontFamily.battlefrontUI),
                  ),
                ],
              ),
            ),
          );
        }

        return const SizedBox();
      },
    );
  }
}
