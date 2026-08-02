import 'package:get/get.dart';

import '../screens/splash_screen.dart';
import '../screens/home_screen.dart';
import '../screens/model_library_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/api_endpoints_screen.dart';
import '../screens/logs_screen.dart';
import '../screens/lua_tools_screen.dart';
import '../screens/tools_hub_screen.dart';
import '../screens/script_runner_screen.dart';
import '../screens/unc_checker_screen.dart';

class AppRoutes {
  static const splash = '/splash';
  static const home = '/home';
  static const modelLibrary = '/models';
  static const settings = '/settings';
  static const apiEndpoints = '/api-endpoints';
  static const logs = '/logs';
  static const luaTools = '/lua-tools';
  static const toolsHub = '/tools-hub';
  static const scriptRunner = '/script-runner';
  static const uncChecker = '/unc-checker';

  static final pages = [
    GetPage(name: splash, page: () => const SplashScreen()),
    GetPage(name: home, page: () => const HomeScreen()),
    GetPage(
      name: modelLibrary,
      page: () => const ModelLibraryScreen(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: settings,
      page: () => const SettingsScreen(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: apiEndpoints,
      page: () => const ApiEndpointsScreen(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: logs,
      page: () => const LogsScreen(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: luaTools,
      page: () => const LuaToolsScreen(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: toolsHub,
      page: () => const ToolsHubScreen(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: scriptRunner,
      page: () => const ScriptRunnerScreen(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: uncChecker,
      page: () => const UncCheckerScreen(),
      transition: Transition.rightToLeft,
    ),
  ];
}
