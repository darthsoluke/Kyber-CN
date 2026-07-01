import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/core.dart';
import 'package:kyber_launcher/features/kyber/dialogs/kyber_anti_virus_exclusion.dart';
import 'package:kyber_launcher/features/kyber/services/server_join_confirmation_service.dart';
import 'package:kyber_launcher/features/maxima/dialogs/maxima_expired_session_dialog.dart';
import 'package:kyber_launcher/features/maxima/dialogs/maxima_game_locator_dialog.dart';
import 'package:kyber_launcher/features/maxima/dialogs/maxima_game_not_found_dialog.dart';
import 'package:kyber_launcher/features/maxima/helper/maxima_helper.dart';
import 'package:kyber_launcher/features/mods/helper/preloaded_mods_helper.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/gen/rust/api/maxima.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class MaximaStartGameDialog extends StatefulWidget {
  const MaximaStartGameDialog({
    super.key,
    this.gameDataDir,
    this.initializeRequest,
    this.mods,
  });

  final String? gameDataDir;
  final List<FrostyMod>? mods;
  final InitializeRequest? initializeRequest;

  @override
  State<MaximaStartGameDialog> createState() => _MaximaStartGameDialogState();
}

class MaximaLaunchResult {
  const MaximaLaunchResult._({required this.success, this.message});

  const MaximaLaunchResult.success() : this._(success: true);

  const MaximaLaunchResult.failure(String message)
    : this._(success: false, message: message);

  final bool success;
  final String? message;
}

enum _MaximaLaunchMode {
  game,
  joinServer,
  dedicatedServer,
}

class _MaximaStartGameDialogState extends State<MaximaStartGameDialog> {
  final Logger _logger = Logger('maxima_start_game_dialog');

  bool updating = false;
  bool preloadingMods = false;
  String? lastEvent;

  bool _isDirectJoinId(String id) {
    return id.startsWith('lan:') || id.startsWith('direct:');
  }

  bool _isOfflineDirectRequest(InitializeRequest request) {
    if (request.hasStartServer() &&
        request.startServer.hasOnlineMode() &&
        !request.startServer.onlineMode) {
      return true;
    }

    if (request.hasJoinServer()) {
      final joinServer = request.joinServer;
      return joinServer.joinToken.isEmpty && _isDirectJoinId(joinServer.id);
    }

    return false;
  }

  bool _isDedicatedServerRequest(InitializeRequest request) {
    return request.hasStartServer() &&
        request.startServer.hasOnlineMode() &&
        !request.startServer.onlineMode;
  }

  bool _isJoinServerRequest(InitializeRequest request) {
    return request.hasJoinServer();
  }

  _MaximaLaunchMode _launchMode(InitializeRequest request) {
    if (_isDedicatedServerRequest(request)) {
      return _MaximaLaunchMode.dedicatedServer;
    }

    if (_isJoinServerRequest(request)) {
      return _MaximaLaunchMode.joinServer;
    }

    return _MaximaLaunchMode.game;
  }

  bool _requiresModuleModSupport(InitializeRequest request) {
    if (!request.hasModData()) {
      return false;
    }

    return request.modData.modPaths.isNotEmpty ||
        request.modData.mods.isNotEmpty ||
        request.modData.explodedMods.isNotEmpty;
  }

  @override
  void initState() {
    SchedulerBinding.instance.addPostFrameCallback((_) => _start());
    super.initState();
  }

  Future<void> _start() async {
    final req = widget.initializeRequest ?? .new();
    final initialMode = _launchMode(req);
    _logger.info(
      'DIRECT_STAGE[maxima.dialog.start] '
      'mode=${initialMode.name} hasJoin=${req.hasJoinServer()} '
      'hasStartServer=${req.hasStartServer()} hasModData=${req.hasModData()} '
      'offlineDirect=${_isOfflineDirectRequest(req)}',
    );
    if (req.hasJoinServer()) {
      _logger.info(
        'DIRECT_STAGE[maxima.dialog.join.request] '
        'id=${req.joinServer.id} '
        'ip=${req.joinServer.ip}:${req.joinServer.port} '
        'type=${req.joinServer.type.name} '
        'joinTokenPresent=${req.joinServer.joinToken.isNotEmpty} '
        'passwordPresent=${req.joinServer.password.isNotEmpty}',
      );
    }

    _setLastEvent('maxima.progress.prepareModule');
    final moduleVersionService = ModuleVersionService();
    final requiresModSupport = _requiresModuleModSupport(req);
    try {
      await moduleVersionService.installBundledModuleIfAvailable(
        requireModSupport: requiresModSupport,
      );
    } on Object catch (e, st) {
      Logger.root.warning(
        'Failed to prepare bundled module.',
        e,
        st,
      );
    }

    final hasBundledModule = moduleVersionService.hasLaunchableModule(
      requireModSupport: requiresModSupport,
    );
    if (!hasBundledModule) {
      const message =
          'Bundled Kyber module is missing or incomplete. '
          'Please re-extract the full Release package.';
      Logger.root.severe(message);
      NotificationService.showNotification(
        message: message,
        severity: InfoBarSeverity.error,
      );
      _logger.severe(
        'DIRECT_STAGE[maxima.dialog.module.missing] '
        'requireModSupport=$requiresModSupport',
      );
      _finishFailure(message);
      return;
    }

    try {
      await _prepareMods(req);
      _setLastEvent('maxima.progress.checkService');
      await checkService();
      final launchMode = _launchMode(req);
      final joinConfirmation = ServerJoinConfirmationService();
      if (launchMode == _MaximaLaunchMode.joinServer) {
        joinConfirmation.resetJoinSignal();
      }

      _setLastEvent('maxima.progress.launchBfii');
      _logger.info(
        'DIRECT_STAGE[maxima.dialog.launch.start] mode=${launchMode.name}',
      );
      final instance = await MaximaHelper.startGame(
        gameDataPath: widget.gameDataDir,
        initializeRequest: req,
        mods: widget.mods,
      );
      _logger.info(
        'DIRECT_STAGE[maxima.dialog.launch.done] '
        'mode=${launchMode.name} pid=${instance.pid}',
      );
      if (!mounted) {
        return;
      }

      if (launchMode == _MaximaLaunchMode.dedicatedServer) {
        _finishSuccess();
        return;
      }

      await joinConfirmation.waitForClientInterface(
        instance,
        onProgress: _setLastEvent,
      );
      if (launchMode == _MaximaLaunchMode.joinServer) {
        await joinConfirmation.waitForJoin(
          instance,
          req.joinServer,
          onProgress: _setLastEvent,
        );
      }

      _finishSuccess();
    } on Object catch (error, stackTrace) {
      _handleLaunchError(error, stackTrace);
    }
  }

  Future<void> _prepareMods(InitializeRequest req) async {
    final offlineDirectRequest = _isOfflineDirectRequest(req);
    if (Preferences.general.enabledPreloadMods && !offlineDirectRequest) {
      _setLastEvent('maxima.progress.preloadMods');
      setState(() => preloadingMods = true);
      final preloadedMods = await PreloadedModsHelper.preloadMods();
      if (!mounted) {
        return;
      }

      req.modData = .new(
        mods: req.modData.mods,
        explodedMods: req.modData.explodedMods,
        basePath: req.modData.basePath,
        modPaths: [
          ...req.modData.modPaths,
          ...preloadedMods,
        ],
      );
    } else if (offlineDirectRequest) {
      Logger.root.info(
        'LAN_STAGE[maxima.dialog.preloaded_mods.skip] '
        'reason=offline_direct',
      );
    }
  }

  void _handleLaunchError(Object error, StackTrace stackTrace) {
    final message = _launchErrorMessage(error);
    _logger.severe(
      'DIRECT_STAGE[maxima.dialog.launch.error] message=$message',
      error,
      stackTrace,
    );

    if (error is AnyhowException) {
      if (error.message.contains('Game not found')) {
        unawaited(
          showKyberDialog(
            context: navigatorKey.currentContext!,
            builder: (_) => const MaximaGameNotFoundDialog(),
          ),
        );
      } else if (error.message.contains('Game not installed')) {
        unawaited(
          showKyberDialog(
            context: navigatorKey.currentContext!,
            builder: (_) => const MaximaGameLocatorDialog(),
          ),
        );
      } else if (error.message.contains('remote io error')) {
        unawaited(
          showKyberDialog(
            context: navigatorKey.currentContext!,
            builder: (_) => const KyberAntiVirusExclusion(),
          ),
        );
      } else if (error.message.contains('invalid redirect')) {
        unawaited(
          showKyberDialog(
            context: navigatorKey.currentContext!,
            builder: (_) => const MaximaExpiredSessionDialog(),
          ),
        );
      }

      NotificationService.showNotification(
        message: Localization.current.text(
          'maxima.failedToStartGame',
          params: {'message': error.message},
        ),
        severity: InfoBarSeverity.error,
      );
    } else if (error is PanicException) {
      unawaited(
        showKyberDialog(
          context: navigatorKey.currentContext!,
          builder: (context) {
            final l10n = context.l10n;
            return KyberContentDialog(
              title: Text(l10n.text('maxima.failedToStartGameTitle')),
              content: Text(
                error.message,
                style: const TextStyle(
                  fontFamily: FontFamily.battlefrontUI,
                  fontSize: 17,
                ),
              ),
              actions: [
                KyberButton(
                  onPressed: () => Navigator.of(context).pop(),
                  text: l10n.text('common.close'),
                ),
              ],
            );
          },
        ),
      );
    } else {
      NotificationService.showNotification(
        message: Localization.current.text(
          'maxima.failedToStartGame',
          params: {'message': '$error'},
        ),
        severity: InfoBarSeverity.error,
      );
    }

    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
    Logger.root.severe(
      'Failed to start game: $error',
      error,
      stackTrace,
    );
    _finishFailure(message);
  }

  String _launchErrorMessage(Object error) {
    if (error is AnyhowException) {
      return error.message;
    }

    if (error is PanicException) {
      return error.message;
    }

    return '$error';
  }

  void _finishSuccess() {
    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(const MaximaLaunchResult.success());
  }

  void _finishFailure(String message) {
    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(MaximaLaunchResult.failure(message));
  }

  void _setLastEvent(String messageKey) {
    if (!mounted) {
      return;
    }

    setState(() => lastEvent = Localization.current.text(messageKey));
  }

  @override
  void dispose() => super.dispose();

  String _titleKey(_MaximaLaunchMode launchMode) {
    return switch (launchMode) {
      _MaximaLaunchMode.dedicatedServer => 'maxima.dedicatedLaunching',
      _MaximaLaunchMode.joinServer => 'maxima.joinLaunching',
      _MaximaLaunchMode.game => 'maxima.gameLaunching',
    };
  }

  String _startingKey(_MaximaLaunchMode launchMode) {
    return switch (launchMode) {
      _MaximaLaunchMode.dedicatedServer => 'maxima.startingDedicated',
      _MaximaLaunchMode.joinServer => 'maxima.startingJoin',
      _MaximaLaunchMode.game => 'maxima.startingGame',
    };
  }

  String _descriptionKey(_MaximaLaunchMode launchMode) {
    return switch (launchMode) {
      _MaximaLaunchMode.dedicatedServer =>
        'maxima.startingDedicatedDescription',
      _MaximaLaunchMode.joinServer => 'maxima.startingJoinDescription',
      _MaximaLaunchMode.game => 'maxima.startingGameDescription',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final launchMode = _launchMode(
      widget.initializeRequest ?? InitializeRequest(),
    );
    return KyberContentDialog(
      title: Text(l10n.text(_titleKey(launchMode))),
      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 300),
      content: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                height: 15,
                width: 15,
                child: RepaintBoundary(child: ProgressRing()),
              ),
              const SizedBox(
                width: 15,
              ),
              if (updating)
                Text(
                  l10n.text('maxima.updatingModule'),
                  style: FluentTheme.of(context).typography.bodyLarge,
                ),
              if (!updating)
                Text(
                  l10n.text(_startingKey(launchMode)),
                  style: FluentTheme.of(context).typography.bodyLarge,
                ),
            ],
          ),
          const SizedBox(
            height: 10,
          ),
          Text(
            l10n.text(_descriptionKey(launchMode)),
            style: FluentTheme.of(context).typography.body?.copyWith(
              color: kWhiteColor,
            ),
          ),
          const SizedBox(
            height: 10,
          ),
          Text(
            lastEvent ?? '',
            style: FluentTheme.of(context).typography.body,
          ),
        ],
      ),
    );
  }
}
