/// BFII host-server compatibility layer.
///
/// The current "server" path launches Battlefront II as a Frostbite host
/// process and injects Kyber into it. These aliases make that boundary explicit
/// without breaking the older DedicatedServer* implementation files yet.
library;

import 'package:kyber_cli/controllers/dedicated_server_launch_controller.dart';
import 'package:kyber_cli/controllers/dedicated_server_mod_controller.dart';
import 'package:kyber_cli/controllers/dedicated_server_session_controller.dart';
import 'package:kyber_cli/models/dedicated_server_auth_context.dart';
import 'package:kyber_cli/models/dedicated_server_launch_config.dart';
import 'package:kyber_cli/models/dedicated_server_mod_config.dart';
import 'package:kyber_cli/models/dedicated_server_session_config.dart';
import 'package:kyber_cli/services/dedicated_server_auth_service.dart';
import 'package:kyber_cli/services/dedicated_server_license_service.dart';
import 'package:kyber_cli/services/dedicated_server_mod_runtime_service.dart';
import 'package:kyber_cli/services/dedicated_server_runtime_service.dart';

typedef BfiiHostAuthContext = DedicatedServerAuthContext;
typedef BfiiHostLaunchConfig = DedicatedServerLaunchConfig;
typedef BfiiHostModConfig = DedicatedServerModConfig;
typedef BfiiHostSessionConfig = DedicatedServerSessionConfig;

typedef BfiiHostConfigException = DedicatedServerConfigException;
typedef BfiiHostModConfigException = DedicatedServerModConfigException;
typedef BfiiHostSessionConfigException = DedicatedServerSessionConfigException;
typedef BfiiHostAuthException = DedicatedServerAuthException;
typedef BfiiHostLicenseException = DedicatedServerLicenseException;
typedef BfiiHostModRuntimeException = DedicatedServerModRuntimeException;
typedef BfiiHostRuntimeException = DedicatedServerRuntimeException;

typedef BfiiHostLaunchController = DedicatedServerLaunchController;
typedef BfiiHostModController = DedicatedServerModController;
typedef BfiiHostSessionController = DedicatedServerSessionController;

typedef BfiiHostAuthService = DedicatedServerAuthService;
typedef BfiiHostLicenseConfig = DedicatedServerLicenseConfig;
typedef BfiiHostLicenseService = DedicatedServerLicenseService;
typedef BfiiHostModRuntimeService = DedicatedServerModRuntimeService;
typedef BfiiHostRuntimeService = DedicatedServerRuntimeService;
