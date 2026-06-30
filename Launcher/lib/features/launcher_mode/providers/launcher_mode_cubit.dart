import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/features/launcher_mode/models/launcher_mode.dart';

class LauncherModeState {
  const LauncherModeState({this.mode});

  final LauncherMode? mode;

  bool get hasSelection => mode != null;
  bool get isDedicatedOnly => mode?.isDedicatedOnly ?? false;
  bool get isLanOnly => isDedicatedOnly;
  bool get requiresOnlineAccount => mode?.requiresOnlineAccount ?? false;
}

class LauncherModeCubit extends Cubit<LauncherModeState> {
  LauncherModeCubit() : super(const LauncherModeState());

  void selectDedicated() =>
      emit(const LauncherModeState(mode: LauncherMode.dedicated));

  void selectLan() => selectDedicated();

  void selectOnline() =>
      emit(const LauncherModeState(mode: LauncherMode.online));

  void clear() => emit(const LauncherModeState());
}
