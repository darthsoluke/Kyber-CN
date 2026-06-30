import 'package:flutter/widgets.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';

typedef HostStartProgressSink = void Function(HostStartProgressEvent event);

enum HostStartProgressStatus {
  running,
  success,
  error,
}

class HostStartProgressEvent {
  HostStartProgressEvent({
    this.messageKey,
    this.message,
    this.params = const {},
    this.status = HostStartProgressStatus.running,
    DateTime? timestamp,
  }) : assert(
         messageKey != null || message != null,
         'A host start progress event needs a localization key or raw message.',
       ),
       timestamp = timestamp ?? DateTime.now();

  final String? messageKey;
  final String? message;
  final Map<String, Object?> params;
  final HostStartProgressStatus status;
  final DateTime timestamp;

  String resolve(BuildContext context) {
    final rawMessage = message;
    if (rawMessage != null) {
      return rawMessage;
    }

    return context.l10n.text(messageKey!, params: params);
  }
}
