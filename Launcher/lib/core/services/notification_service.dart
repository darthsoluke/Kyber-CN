import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/gen/assets.gen.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:toastification/toastification.dart';

class NotificationService {
  static void notImplemented() {
    showNotification(
      message: Localization.current.text('common.notImplemented'),
      severity: InfoBarSeverity.warning,
    );
  }

  static void warning({required String message, String? title}) {
    showNotification(
      message: message,
      title: title,
      severity: InfoBarSeverity.warning,
    );
  }

  static void error({required String message, String? title}) {
    showNotification(
      message: message,
      title: title,
      severity: InfoBarSeverity.error,
    );
  }

  static void success({required String message, String? title}) {
    showNotification(
      message: message,
      title: title,
      severity: InfoBarSeverity.success,
    );
  }

  static void info({required String message, String? title}) {
    showNotification(
      message: message,
      title: title,
      severity: InfoBarSeverity.info,
    );
  }

  static void showNotification({
    required String message,
    BuildContext? context,
    String? title,
    InfoBarSeverity? severity,
  }) {
    late Color color;
    switch (severity ?? InfoBarSeverity.info) {
      case InfoBarSeverity.info:
        color = Colors.blue;
      case InfoBarSeverity.warning:
        color = Colors.orange;
      case InfoBarSeverity.success:
        color = Colors.green;
      case InfoBarSeverity.error:
        color = Colors.red;
    }

    toastification.show(
      context: context,
      type: ToastificationType.info,
      style: ToastificationStyle.flat,
      title: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontFamily: FontFamily.battlefrontUI,
        ),
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
      ),
      icon: Assets.icons.kblKyberServer.svg(
        height: 20,
        color: color,
      ),
      primaryColor: Colors.transparent,
      alignment: Alignment.bottomCenter,
      backgroundColor: Colors.black.withOpacity(.5),
      foregroundColor: Colors.white,
      borderSide: const BorderSide(color: decoColor, width: 2),
      animationDuration: const Duration(milliseconds: 500),
      autoCloseDuration: const Duration(seconds: 5),
      showProgressBar: false,
      animationBuilder: (context, animation, alignment, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      borderRadius: BorderRadius.circular(kDefaultInnerBorderRadius),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      dragToClose: false,
      pauseOnHover: false,
      applyBlurEffect: true,
    );
  }
}
