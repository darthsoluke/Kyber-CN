import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/features/launcher_mode/providers/launcher_mode_cubit.dart';
import 'package:kyber_launcher/features/maxima/widgets/maxima_navigation_bar_widget.dart';
import 'package:kyber_launcher/features/navigation_bar/widgets/window_buttons.dart';

class ActionBar extends StatelessWidget {
  const ActionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final dedicatedOnly = context
        .watch<LauncherModeCubit>()
        .state
        .isDedicatedOnly;

    return SizedBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          if (dedicatedOnly)
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 8),
              child: Button(
                onPressed: () => context.go('/mode'),
                child: Text(context.l10n.text('mode.switch')),
              ),
            )
          else
            const RepaintBoundary(child: MaximaNavigationBarWidget()),
          const WindowButtons(),
        ],
      ),
    );
  }
}
