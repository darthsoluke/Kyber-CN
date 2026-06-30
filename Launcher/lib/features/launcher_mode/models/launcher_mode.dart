enum LauncherMode {
  dedicated,
  online
  ;

  bool get isDedicatedOnly => this == LauncherMode.dedicated;

  bool get isLanOnly => isDedicatedOnly;

  bool get requiresOnlineAccount => this == LauncherMode.online;
}
