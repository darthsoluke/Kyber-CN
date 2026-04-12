import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class HostingDefaultCard extends StatefulWidget {
  const HostingDefaultCard({super.key});

  @override
  State<HostingDefaultCard> createState() => _HostingDefaultCardState();
}

class _HostingDefaultCardState extends State<HostingDefaultCard> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KyberCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 65,
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.text('host.securitySettings.title'),
                  style: const TextStyle(
                    fontFamily: FontFamily.battlefrontUI,
                    fontSize: 21,
                    height: 1.2,
                  ),
                ),
                Text(
                  l10n.text('host.securitySettings.description'),
                  style: const TextStyle(
                    fontFamily: FontFamily.battlefrontUI,
                    fontSize: 14,
                    color: kWhiteColor,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 2,
            color: decoColor,
          ),
        ],
      ),
    );
  }
}
