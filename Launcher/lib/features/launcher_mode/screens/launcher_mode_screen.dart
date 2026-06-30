import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/features/launcher_mode/providers/launcher_mode_cubit.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/utils/background_blur.dart';

class LauncherModeScreen extends StatelessWidget {
  const LauncherModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dedicatedCard = _ModeCard(
      title: l10n.text('mode.lan.title'),
      eyebrow: l10n.text('mode.lan.eyebrow'),
      description: l10n.text('mode.lan.description'),
      actionText: l10n.text('mode.lan.action'),
      accent: const Color(0xFF78D5A5),
      onPressed: () {
        context.read<LauncherModeCubit>().selectDedicated();
        context.go('/server_host?mode=dedicated');
      },
    );
    final onlineCard = _ModeCard(
      title: l10n.text('mode.online.title'),
      eyebrow: l10n.text('mode.online.eyebrow'),
      description: l10n.text('mode.online.description'),
      actionText: l10n.text('mode.online.action'),
      accent: kActiveColor,
      onPressed: () {
        context.read<LauncherModeCubit>().selectOnline();
        context.go('/home');
      },
    );

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, viewport) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: viewport.maxHeight - 48,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.text('mode.title'),
                        style: FluentTheme.of(context).typography.title
                            ?.copyWith(
                              fontFamily: FontFamily.battlefrontUI,
                              fontSize: 38,
                              height: 1.16,
                              color: kActiveColor,
                              shadows: [
                                Shadow(
                                  color: kActiveColor.withValues(alpha: .3),
                                  blurRadius: 24,
                                ),
                              ],
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.text('mode.subtitle'),
                        style: FluentTheme.of(context).typography.bodyLarge
                            ?.copyWith(
                              height: 1.28,
                              color: kWhiteColor.withValues(alpha: .82),
                            ),
                      ),
                      const SizedBox(height: 28),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 760) {
                            return Column(
                              children: [
                                dedicatedCard,
                                const SizedBox(height: 14),
                                onlineCard,
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: dedicatedCard),
                              const SizedBox(width: 18),
                              Expanded(child: onlineCard),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ModeCard extends StatefulWidget {
  const _ModeCard({
    required this.title,
    required this.eyebrow,
    required this.description,
    required this.actionText,
    required this.accent,
    required this.onPressed,
  });

  final String title;
  final String eyebrow;
  final String description;
  final String actionText;
  final Color accent;
  final VoidCallback onPressed;

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        scale: _hovered ? 1.015 : 1,
        child: SizedBox(
          height: 320,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kDefaultOuterBorderRadius),
            child: BackgroundBlur(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    kDefaultOuterBorderRadius,
                  ),
                  border: Border.all(
                    color: _hovered
                        ? widget.accent
                        : kWhiteColor.withValues(alpha: .26),
                    width: _hovered ? 1.5 : 1,
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.accent.withValues(alpha: _hovered ? .2 : .12),
                      Colors.black.withValues(alpha: .46),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.eyebrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FontFamily.battlefrontUI,
                        fontSize: 13,
                        height: 1.18,
                        letterSpacing: 1.4,
                        color: widget.accent,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: FluentTheme.of(context).typography.subtitle
                          ?.copyWith(
                            fontFamily: FontFamily.battlefrontUI,
                            fontSize: 25,
                            height: 1.16,
                            color: kWhiteColor,
                          ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Text(
                        widget.description,
                        overflow: TextOverflow.fade,
                        style: FluentTheme.of(context).typography.body
                            ?.copyWith(
                              color: kWhiteColor.withValues(alpha: .78),
                              height: 1.35,
                            ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: KyberButton(
                        text: widget.actionText,
                        onPressed: widget.onPressed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
