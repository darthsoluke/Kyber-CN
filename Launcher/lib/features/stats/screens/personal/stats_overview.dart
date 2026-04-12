import 'package:auto_size_text/auto_size_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:intl/intl.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/features/maxima/providers/maxima_cubit.dart';
import 'package:kyber_launcher/features/stats/models/stats_object.dart';
import 'package:kyber_launcher/features/stats/providers/stats_cubit.dart';
import 'package:kyber_launcher/gen/assets.gen.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/cards/kyber_container.dart';
import 'package:kyber_launcher/shared/ui/elements/kyber_tab_bar.dart';
import 'package:kyber_launcher/shared/ui/primitives/rank_icon.dart';

class UserStats extends StatefulWidget {
  const UserStats({super.key});

  @override
  State<UserStats> createState() => _UserStatsState();
}

String formatPlaytime(BuildContext context, Duration duration) {
  final l10n = context.l10n;
  if (duration.inHours > 0) {
    return '${NumberFormat.decimalPattern().format(duration.inHours)} ${l10n.text('stats.time.hours')}';
  } else if (duration.inMinutes > 0) {
    return '${duration.inMinutes} ${l10n.text('stats.time.minutes')}';
  } else {
    return '${duration.inSeconds} ${l10n.text('stats.time.seconds')}';
  }
}

String localizeStatsName(BuildContext context, String name) {
  final l10n = context.l10n;
  switch (name) {
    case 'Boba Fett':
      return l10n.text('stats.hero.bobaFett');
    case 'Bossk':
      return l10n.text('stats.hero.bossk');
    case 'Darth Vader':
      return l10n.text('stats.hero.darthVader');
    case 'Emperor':
      return l10n.text('stats.hero.emperor');
    case 'Grievous':
      return l10n.text('stats.hero.grievous');
    case 'Iden':
      return l10n.text('stats.hero.iden');
    case 'Kylo Ren':
      return l10n.text('stats.hero.kyloRen');
    case 'Maul':
      return l10n.text('stats.hero.maul');
    case 'Phasma':
      return l10n.text('stats.hero.phasma');
    case 'Dooku':
      return l10n.text('stats.hero.dooku');
    case 'BB9E':
      return l10n.text('stats.hero.bb9E');
    case 'Chewbacca':
      return l10n.text('stats.hero.chewbacca');
    case 'Han Solo':
      return l10n.text('stats.hero.hanSolo');
    case 'Lando':
      return l10n.text('stats.hero.lando');
    case 'Leia':
      return l10n.text('stats.hero.leia');
    case 'Luke':
      return l10n.text('stats.hero.luke');
    case 'Rey':
      return l10n.text('stats.hero.rey');
    case 'Yoda':
      return l10n.text('stats.hero.yoda');
    case 'Finn':
      return l10n.text('stats.hero.finn');
    case 'Obi Wan':
      return l10n.text('stats.hero.obiWan');
    case 'Anakin':
      return l10n.text('stats.hero.anakin');
    case 'BB8':
      return l10n.text('stats.hero.bb8');
    case 'Assault':
      return l10n.text('stats.class.assault');
    case 'Heavy':
      return l10n.text('stats.class.heavy');
    case 'Officer':
      return l10n.text('stats.class.officer');
    case 'Specialist':
      return l10n.text('stats.class.specialist');
    case 'Infantry':
      return l10n.text('stats.entity.infantry');
    case 'Aerial':
      return l10n.text('stats.entity.aerial');
    case 'Enforcer':
      return l10n.text('stats.entity.enforcer');
    case 'Infiltrator':
      return l10n.text('stats.entity.infiltrator');
    case 'Heroes':
      return l10n.text('stats.entity.heroes');
    case 'Armored':
      return l10n.text('stats.entity.armored');
    case 'Artillery':
      return l10n.text('stats.entity.artillery');
    case 'Speeder':
      return l10n.text('stats.entity.speeder');
    case 'Ground Vehicle':
      return l10n.text('stats.vehicle.armor');
    case 'Fighter':
      return l10n.text('stats.entity.fighter');
    case 'Interceptor':
      return l10n.text('stats.entity.interceptor');
    case 'Bomber':
      return l10n.text('stats.entity.bomber');
    default:
      return name.toUpperCase();
  }
}

class _UserStatsState extends State<UserStats> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: BlocBuilder<StatsCubit, StatsState>(
            builder: (context, state) {
              if (state is StatsError) {
                return Center(child: Text(state.error));
              }

              if (state is! StatsLoaded) {
                return const Center(child: ProgressRing());
              }

              if (state.playerStats == null) {
                return Center(child: Text(context.l10n.text('stats.noStatsFound')));
              }

              return Padding(
                padding: kDefaultPadding,
                child: Row(
                  spacing: 15,
                  children: [
                    Expanded(
                      flex: 5,
                      child: KyberCard(
                        padding: .zero,
                        child: Column(
                          crossAxisAlignment: .stretch,
                          children: [
                            SizedBox(
                              height: 61,
                              child: Padding(
                                padding: const .all(8),
                                child: Row(
                                  spacing: 5,
                                  mainAxisAlignment: .spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        spacing: 12,
                                        children: [
                                          Container(
                                            height: 45,
                                            decoration: BoxDecoration(
                                              border: kDefaultAllBorder,
                                              borderRadius: .circular(
                                                kDefaultInnerBorderRadius,
                                              ),
                                            ),
                                            child: ClipRRect(
                                              borderRadius: .circular(
                                                kDefaultInnerBorderRadius - 2,
                                              ),
                                              child: CachedNetworkImage(
                                                imageUrl: context
                                                    .read<MaximaCubit>()
                                                    .state
                                                    .servicePlayer!
                                                    .avatar!
                                                    .large
                                                    .path,
                                                fadeInDuration: .zero,
                                              ),
                                            ),
                                          ),
                                          Flexible(
                                            child: Column(
                                              crossAxisAlignment: .start,
                                              mainAxisAlignment: .center,
                                              children: [
                                                Text(
                                                  context
                                                      .read<MaximaCubit>()
                                                      .state
                                                      .servicePlayer!
                                                      .displayName,
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontFamily: FontFamily
                                                        .battlefrontUI,
                                                    height: 1.1,
                                                  ),
                                                ),
                                                AutoSizeText(
                                                  formatPlaytime(
                                                    context,
                                                    state.playerStats!.totalPlaytime,
                                                  ),
                                                  style: const TextStyle(
                                                    height: 1.1,
                                                    fontFamily: FontFamily
                                                        .battlefrontUI,
                                                    color: kWhiteColor1,
                                                  ),
                                                  maxLines: 1,
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            height: 40,
                                            width: 40,
                                            child: RankIcon(
                                              level:
                                                  state.playerStats!.playerRank,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: 80,
                                      height: 38,
                                      child: KyberTabBar(
                                        tabs: [
                                          Assets.logos.eaPlay.svg(),
                                          Assets.logos.kyberLight.svg(),
                                        ],
                                        selectedIndex:
                                            state.statsSource ==
                                                StatsSource.EA_PC
                                            ? 0
                                            : 1,
                                        onChanged:
                                            context
                                                .read<StatsCubit>()
                                                .hasKBStats
                                            ? (index) {
                                                context
                                                    .read<StatsCubit>()
                                                    .fetchStats(
                                                      statsSource: index == 0
                                                          ? StatsSource.EA_PC
                                                          : StatsSource.KYBER,
                                                    );
                                              }
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const CardSection(),
                            Container(
                              height: 150,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 5,
                              ),
                              child: Row(
                                spacing: 15,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  for (var i = 0; i < 3; i++)
                                    Expanded(
                                      child: Builder(
                                        builder: (context) {
                                          final char = state.playerStats!
                                              .getCharactersByPlaytime()
                                              .elementAt(i);
                                          return SizedBox(
                                            width: 100,
                                            height: 150,
                                            child: Column(
                                              children: [
                                                Flexible(
                                                  child: Container(
                                                    margin:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 15,
                                                          vertical: 15,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      border: kDefaultAllBorder,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            kDefaultInnerBorderRadius,
                                                          ),
                                                    ),
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            kDefaultInnerBorderRadius -
                                                                2,
                                                          ),
                                                      child: Stack(
                                                        children: [
                                                          Positioned.fill(
                                                            child: ColorFiltered(
                                                              colorFilter:
                                                                  ColorFilter.mode(
                                                                    Colors.black
                                                                        .withOpacity(
                                                                          0.5,
                                                                        ),
                                                                    BlendMode
                                                                        .srcOver,
                                                                  ),
                                                              child: Assets
                                                                  .images
                                                                  .kyberNoImage
                                                                  .image(
                                                                    fit: BoxFit
                                                                        .cover,
                                                                  ),
                                                            ),
                                                          ),
                                                          SizedBox(
                                                            width: 55,
                                                            height: 55,
                                                            child: char
                                                                .getPortraitWidget(),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(
                                                  height: 50,
                                                  child: Column(
                                                    children: [
                                                      Text(
                                                        context.l10n.text(
                                                          'stats.mostPlayed',
                                                        ),
                                                        style: const TextStyle(
                                                          fontFamily: FontFamily
                                                              .battlefrontUI,
                                                          color: kWhiteColor1,
                                                          fontSize: 15,
                                                          height: 1.1,
                                                        ),
                                                      ),
                                                      Text(
                                                        localizeStatsName(
                                                          context,
                                                          char.name,
                                                        ),
                                                        style: const TextStyle(
                                                          fontFamily: FontFamily
                                                              .battlefrontUI,
                                                          fontSize: 15,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const CardSection(),
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.all(15),
                                child: Builder(
                                  builder: (context) {
                                    final stats = {
                                      context.l10n.text('stats.totalKills'):
                                          NumberFormat.decimalPattern().format(
                                            state.playerStats!.totalKills,
                                          ),
                                      context.l10n.text('stats.totalDeaths'):
                                          NumberFormat.decimalPattern().format(
                                            state.playerStats!.totalDeaths,
                                          ),
                                      context.l10n.text('stats.kdRatio'): state.playerStats!
                                          .getKd()
                                          .toStringAsFixed(2),
                                      context.l10n.text('stats.assists'): NumberFormat.decimalPattern()
                                          .format(
                                            state.playerStats!.eliminations,
                                          ),
                                      context.l10n.text('stats.damageDone'):
                                          NumberFormat.decimalPattern().format(
                                            state.playerStats!.totalScore,
                                          ),
                                      context.l10n.text('stats.suicides'): NumberFormat.decimalPattern()
                                          .format(state.playerStats!.suicides),
                                      context.l10n.text('stats.gamesWon'): NumberFormat.decimalPattern()
                                          .format(state.playerStats!.totalWins),
                                      context.l10n.text('stats.gamesLost'):
                                          NumberFormat.decimalPattern().format(
                                            state.playerStats!.totalLosses,
                                          ),
                                      context.l10n.text('stats.winRate'):
                                          '${state.playerStats!.getWinRate().toStringAsFixed(1)}%',
                                    };
                                    return StaggeredGrid.count(
                                      crossAxisCount: 6,
                                      mainAxisSpacing: 15,
                                      crossAxisSpacing: 15,
                                      children: [
                                        for (final entry in stats.entries)
                                          StaggeredGridTile.fit(
                                            crossAxisCellCount: 2,
                                            child: _Stat(
                                              title: entry.key,
                                              value: entry.value,
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 12,
                      child: KyberCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            const SizedBox(
                              height: 61,
                            ),
                            const CardSection(),
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 15,
                                  vertical: 10,
                                ),
                                children: [
                                  _StatSection(
                                    title: context.l10n.text('stats.units'),
                                    data: state.playerStats!.unitStats.values
                                        .toList(),
                                  ),
                                  _StatSection(
                                    title: context.l10n.text('stats.vehicles'),
                                    data: state.playerStats!.vehicleStats.values
                                        .toList(),
                                  ),
                                  _StatSection(
                                    title: context.l10n.text(
                                      'stats.starfighters',
                                    ),
                                    data: state
                                        .playerStats!
                                        .starFighterStats
                                        .values
                                        .toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatSection extends StatelessWidget {
  const _StatSection({
    required this.title,
    required this.data,
  });

  final String title;
  final List<EntityStats> data;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        spacing: 15,
        children: [
          Row(
            spacing: 10,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    kDefaultInnerBorderRadius,
                  ),
                  color: kWhiteColor,
                ),
                child: Assets.icons.kblHero.svg(height: 18),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: FontFamily.battlefrontUI,
                  color: kWhiteColor,
                  fontSize: 18,
                ),
              ),
              Expanded(
                child: Container(
                  height: 2,
                  color: decoColor,
                ),
              ),
            ],
          ),
          Flexible(
            child: Row(
              spacing: 15,
              children: [
                for (int i = 0; i < data.length; i++)
                  Flexible(
                    child: _ClassContainer(
                      name: data[i].name,
                      displayName: localizeStatsName(context, data[i].name),
                      portrait: data[i].portrait,
                      rank: data[i].rank,
                      timePlayed: formatPlaytime(context, data[i].timePlayed),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassContainer extends StatelessWidget {
  const _ClassContainer({
    required this.name,
    required this.displayName,
    required this.timePlayed,
    required this.portrait,
    this.rank,
  });

  final ImageProvider portrait;
  final String name;
  final String displayName;
  final int? rank;
  final String timePlayed;

  @override
  Widget build(BuildContext context) {
    const containerHeight = 287;
    const containerWidth = 220;
    const aspectRatio = containerWidth / containerHeight;
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kDefaultInnerBorderRadius),
          border: kDefaultAllBorder,
          color: Colors.black,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kDefaultInnerBorderRadius - 2),
          child: Stack(
            children: [
              Positioned.fill(
                top: -1,
                left: -1,
                right: -1,
                bottom: -1,
                child: ShaderMask(
                  shaderCallback: (rect) {
                    return LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      stops: const [0.05, 1],
                      colors: [
                        Colors.transparent.withOpacity(0.1),
                        Colors.black,
                      ],
                    ).createShader(
                      Rect.fromLTRB(0, 0, rect.width, rect.height),
                    );
                  },
                  blendMode: BlendMode.dstIn,
                  child: Image(
                    image: portrait,
                    fit: BoxFit.cover,
                    alignment: name.toUpperCase() == 'INFILTRATOR'
                        ? const Alignment(-0.25, 0)
                        : name.toUpperCase() == 'ARTILLERY'
                        ? const Alignment(0.75, 0)
                        : const Alignment(0.65, 0),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: 38,
                          height: 38,
                          child: rank != null
                              ? RankIcon(level: rank!)
                              : Assets.icons.kblStatGroup.svg(),
                        ),
                      ),
                      Column(
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontFamily: FontFamily.battlefrontUI,
                            ),
                          ),
                          Text(
                            timePlayed,
                            style: const TextStyle(
                              fontSize: 15,
                              color: kGrayColor,
                              fontFamily: FontFamily.battlefrontUI,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: FontFamily.battlefrontUI,
            color: kWhiteColor1,
            fontSize: 17,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontFamily: FontFamily.battlefrontUI,
            color: kWhiteColor,
            fontSize: 17,
          ),
        ),
      ],
    );
  }
}
