import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/features/download_manager/models/download_state.dart';
import 'package:kyber_launcher/features/download_manager/providers/download_manager_cubit.dart';
import 'package:kyber_launcher/features/launcher_mode/providers/launcher_mode_cubit.dart';
import 'package:kyber_launcher/shared/ui/navigation_bar/navigation_bar_seperator.dart';
import 'package:kyber_launcher/shared/ui/navigation_bar/widgets/navigation_bar_item.dart';
import 'package:kyber_launcher/shared/ui/navigation_bar/widgets/navigation_bar_sub_item.dart';
import 'package:kyber_launcher/shared/ui/navigation_bar/widgets/navigation_download_info.dart';
import 'package:kyber_launcher/shared/ui/utils/background_blur.dart';

class NavigationBarList extends StatefulWidget {
  const NavigationBarList({required this.route, super.key});

  final String route;

  @override
  State<NavigationBarList> createState() => _NavigationBarListState();
}

class NavigationBarEntry {
  NavigationBarEntry(this.title, this.route);

  String title;
  String route;
}

class _NavigationBarListState extends State<NavigationBarList> {
  int _activeItem = 0;
  bool _hovering = false;
  bool _showPositioned = false;
  int? _hoveringIndex;

  List<NavigationBarEntry> getItems({bool dedicatedOnly = false}) {
    if (dedicatedOnly) {
      return [
        NavigationBarEntry(Localization.current.text('nav.lanJoin'), 'home'),
        NavigationBarEntry(
          Localization.current.text('nav.host'),
          'server_host',
        ),
        NavigationBarEntry(Localization.current.text('nav.mods'), 'mods'),
      ];
    }

    return [
      NavigationBarEntry(Localization.current.text('nav.home'), 'home'),
      NavigationBarEntry(Localization.current.text('nav.host'), 'server_host'),
      NavigationBarEntry(Localization.current.text('nav.stats'), 'stats'),
      NavigationBarEntry(Localization.current.text('nav.mods'), 'mods'),
      NavigationBarEntry(
        Localization.current.text('nav.settings'),
        'settings',
      ),
    ];
  }

  int _routeIndex(List<NavigationBarEntry> items) {
    return items.indexWhere(
      (element) =>
          element.route == widget.route.split('/').last.split('?').first,
    );
  }

  @override
  void didUpdateWidget(covariant NavigationBarList oldWidget) {
    if (oldWidget.route != widget.route) {
      final items = getItems(
        dedicatedOnly: context.read<LauncherModeCubit>().state.isDedicatedOnly,
      );
      final index = _routeIndex(items);

      if (index != -1) {
        setState(() {
          _activeItem = index;
        });
      }
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 20, top: 10),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.centerLeft,
          children: <Widget>[
            ...previousChildren,
            ?currentChild,
          ],
        ),
        child: Builder(
          builder: (context) {
            if (RegExp('/').allMatches(widget.route).length > 1) {
              final routes = widget.route.split('/').skip(1);

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  BackgroundBlur(
                    key: const ValueKey('subNavBarList'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 41,
                          width: 1.5,
                          color: kWhiteColor,
                        ),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          scrollDirection: Axis.horizontal,
                          separatorBuilder: (context, index) =>
                              Transform.rotate(
                                angle: 18 * 3.14 / 180,
                                child: UnconstrainedBox(
                                  child: Container(
                                    height: 20,
                                    width: 2,
                                    color: kGrayColor,
                                  ),
                                ),
                              ),
                          itemBuilder: (context, index) => NavigationBarSubItem(
                            isLast: index == routes.length - 1,
                            route: routes.elementAt(index),
                            index: index,
                            fullRoute: "/${routes.take(index + 1).join("/")}",
                          ),
                          itemCount: routes.length,
                        ),
                        Container(
                          height: 41,
                          width: 1.5,
                          color: kWhiteColor,
                        ),
                      ],
                    ),
                  ),
                  RepaintBoundary(
                    child: BlocBuilder<DownloadCubit, DownloadState>(
                      builder: (context, state) {
                        final currentDownload = state is DownloadLoaded
                            ? state.currentDownload
                            : null;

                        if (currentDownload == null) {
                          return const SizedBox.shrink();
                        }

                        return GestureDetector(
                          onTap: () {
                            router.goNamed('downloads');
                          },
                          child: const NavigationDownloadInfo(),
                        );
                      },
                    ),
                  ),
                ],
              );
            }

            final dedicatedOnly = context
                .watch<LauncherModeCubit>()
                .state
                .isDedicatedOnly;
            final items = getItems(dedicatedOnly: dedicatedOnly);
            final routeIndex = _routeIndex(items);
            final activeItem = routeIndex == -1 ? _activeItem : routeIndex;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ListView.separated(
                      key: const ValueKey('navBarList'),
                      shrinkWrap: true,
                      itemCount: items.length + 2,
                      physics: const NeverScrollableScrollPhysics(),
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.zero,
                      separatorBuilder: (context, index) {
                        final active =
                            index == activeItem || index == activeItem + 1;
                        final hover =
                            _hoveringIndex == index - 1 ||
                            _hoveringIndex == index;
                        return NavigationBarSeperator(
                          active: active,
                          hover: _hovering && hover,
                          showPositioned: active && _showPositioned,
                        );
                      },
                      itemBuilder: (context, index) {
                        if (index == 0 || index == items.length + 1) {
                          return const SizedBox.shrink();
                        }

                        final itemIndex = index - 1;
                        final item = items[itemIndex];
                        final active = _hovering && _hoveringIndex == itemIndex;
                        final child = NavigationBarItem(
                          item: item,
                          onTap: () async {
                            if (widget.route == '/${item.route}') {
                              return;
                            }

                            router.go('/${item.route}');

                            // hack to make the positioned animation work
                            setState(() => _showPositioned = false);
                            await Future<void>.delayed(
                              const Duration(milliseconds: 5),
                            );
                            setState(() {
                              _activeItem = itemIndex;
                              _showPositioned = true;
                            });
                          },
                          onHover: (value) => setState(() {
                            _hovering = value;
                            _hoveringIndex = value ? itemIndex : null;
                          }),
                          active: activeItem == itemIndex,
                          hover: active,
                        );

                        return child;
                      },
                    ),
                    RepaintBoundary(
                      child: BlocBuilder<DownloadCubit, DownloadState>(
                        builder: (context, state) {
                          return MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () {
                                router.goNamed('downloads');
                              },
                              child: const NavigationDownloadInfo(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
