import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/features/kyber/services/map_helper.dart';
import 'package:kyber_launcher/gen/assets.gen.dart';
import 'package:kyber_launcher/injection_container.dart';

class ServerBackgroundImage extends StatelessWidget {
  const ServerBackgroundImage({
    required this.map,
    super.key,
    this.fade = true,
    this.imageId,
    this.blur = true,
  });

  final String map;
  final String? imageId;
  final bool fade;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final image = MapHelper.getImageForMap(map);
    final imageId = this.imageId;
    if (!fade) {
      return ColorFiltered(
        colorFilter: ColorFilter.mode(
          Colors.black.withValues(alpha: 0.7),
          BlendMode.srcATop,
        ),
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: !blur ? 0 : 4,
            sigmaY: !blur ? 0 : 4,
            tileMode: TileMode.mirror,
          ),
          child: imageId != null
              ? CachedNetworkImage(
                  imageUrl: sl.get<KyberGRPCService>().imageUrl(imageId),
                  height: 200,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Assets.images.kyberNoImage.image(
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                )
              : image?.image(
                      height: 200,
                      fit: BoxFit.cover,
                    ) ??
                    Assets.images.kyberNoImage.image(
                      height: 200,
                      fit: BoxFit.cover,
                    ),
        ),
      );
    }

    return ShaderMask(
      shaderCallback: (rect) {
        return LinearGradient(
          begin: .bottomCenter,
          end: .topCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: .4),
          ],
        ).createShader(Rect.fromLTRB(0, 0, rect.width, rect.height));
      },
      blendMode: BlendMode.dstIn,
      child:
          image?.image(
            height: 200,
            fit: .fitWidth,
          ) ??
          Assets.images.kyberNoImage.image(
            height: 200,
            fit: .cover,
          ),
    );
  }
}
