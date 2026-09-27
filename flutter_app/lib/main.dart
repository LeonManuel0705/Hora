// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:ui';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'brand.dart';
import 'providers/app_provider.dart';
import 'providers/bookmark_provider.dart';
import 'providers/notes_provider.dart';
import 'providers/assistant_provider.dart';
import 'providers/iserv_provider.dart';
import 'providers/email_provider.dart';
import 'build_info.dart';
import 'providers/vbb_provider.dart';
import 'providers/sync_provider.dart';
import 'services/connectivity_service.dart';
import 'services/sync_manager.dart';
import 'services/offline_queue.dart';
import 'services/background_service.dart' if (dart.library.html) 'services/background_service_web.dart';
import 'services/notification_service.dart';
import 'services/holiday_service.dart';
import 'services/update_service.dart';
import 'services/calendar_sync_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/tasks_screen.dart' show TasksScreen;
import 'screens/calendar_screen.dart' show CalendarScreen;
import 'screens/school_screen.dart' show SchoolScreen;
import 'screens/more_screen.dart';
import 'screens/pomodoro_screen.dart';
import 'screens/training_screen.dart';
import 'screens/email_screen.dart';
import 'screens/review_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/assistant_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/vbb_screen.dart';
import 'screens/bookmarks_screen.dart';
import 'screens/iserv_screen.dart';
import 'theme.dart';
import 'tutorial/tutorial.dart';
import 'widgets/connection_indicator.dart';
import 'widgets/app_background.dart';
import 'utils/responsive.dart';
import 'utils/platform_utils.dart' if (dart.library.html) 'utils/platform_utils_web.dart';
import 'web_ui/mobile_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Hive.initFlutter().timeout(const Duration(seconds: 5));
  } catch (_) {
  }

  try {
    await initializeDateFormatting('de_DE', null).timeout(const Duration(seconds: 4));
  } catch (_) {
  }

  try {
    await ConnectivityService().initialize().timeout(const Duration(seconds: 4));
  } catch (_) {
  }

  try {
    await OfflineQueue().initialize().timeout(const Duration(seconds: 4));
  } catch (_) {
  }

  try {
    await CalendarSyncService().initialize().timeout(const Duration(seconds: 4));
  } catch (_) {
  }

  if (!kIsWeb) {
    try {
      await SyncManager().initialize();
    } catch (_) {
    }

    // Guard these too — a plugin exception here (e.g. WorkManager/BGTask
    // registration failing on a given OS version) must not abort startup before
    // runApp(), which would leave the user staring at a white screen.
    try {
      await BackgroundService().initialize();
      await BackgroundService().registerTasks();
    } catch (_) {
    }

    if (!const bool.fromEnvironment('UI_QUIET')) {
      try {
        await NotificationService().initialize();
      } catch (_) {
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_app_version', BuildInfo.version);
    } catch (_) {
    }

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider(create: (_) => BookmarkProvider()),
        ChangeNotifierProvider(create: (_) => NotesProvider()),
        ChangeNotifierProvider(create: (_) => AssistantProvider()),
        ChangeNotifierProvider(create: (_) => IServProvider()),
        ChangeNotifierProvider(create: (_) => EmailProvider()),
        ChangeNotifierProvider(create: (_) => VbbProvider()),
        ChangeNotifierProvider(create: (_) => SyncProvider()),
      ],
      child: _AppInitializer(
        builder: (context) => Consumer<AppProvider>(
          builder: (context, provider, child) {
            final isDark = provider.themeMode == ThemeMode.dark ||
                (provider.themeMode == ThemeMode.system &&
                    WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
            if (!kIsWeb) {
              SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
                systemNavigationBarColor: isDark ? AppPalette.canvasDark : AppPalette.canvas,
                systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
              ));
            }

            return MaterialApp(
              title: Brand.name,
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: provider.themeMode,
              themeAnimationDuration: const Duration(milliseconds: 500),
              themeAnimationCurve: Curves.easeInOut,
              navigatorObservers: [Tutorial.observer],
              builder: (context, child) {
                AppTheme.useBrightness(Theme.of(context).brightness);
                return TutorialHost(child: child ?? const SizedBox.shrink());
              },
              home: kIsWeb
                  ? buildClassicHome()
                  : isDesktopPlatform()
                      ? buildDesktopHome()
                      : const MobileShell(),
            );
          },
        ),
      ),
    );
  }
}

Widget buildClassicHome() => MainScreen(key: MainScreen._globalKey);

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  static final _globalKey = GlobalKey<_MainScreenState>();

  static void navigateTo(int screenIndex) {
    _globalKey.currentState?._navigateToScreen(screenIndex);
  }

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentIndex = 0;
  bool _hasCheckedFirstLaunch = false;
  bool _isMobileMenuOpen = false;

  late AnimationController _pageTransitionController;
  late AnimationController _menuSlideController;

  late final List<Widget> _screens;


  static const _sidebarOrder = [0, 1, 2, 3, 6, 8, 11, 13, 7, 12, 5, 14, 9, 10];
  static const _sidebarItemHeight = 40.0;
  static const _pillNavClearance = 76.0;

  static const _bundeslaender = [
    'Baden-Württemberg',
    'Bayern',
    'Berlin',
    'Brandenburg',
    'Bremen',
    'Hamburg',
    'Hessen',
    'Mecklenburg-Vorpommern',
    'Niedersachsen',
    'Nordrhein-Westfalen',
    'Rheinland-Pfalz',
    'Saarland',
    'Sachsen',
    'Sachsen-Anhalt',
    'Schleswig-Holstein',
    'Thüringen',
  ];

  @override
  void initState() {
    super.initState();
    _pageTransitionController = AnimationController(
      vsync: this,
      value: 1,
    );
    _menuSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _screens = [
      const DashboardScreen(),
      const TasksScreen(),
      const CalendarScreen(),
      const SchoolScreen(),
      const MoreScreen(),
      const PomodoroScreen(),
      const TrainingScreen(),
      const EmailScreen(),
      const ReviewScreen(),
      const AssistantScreen(),
      const SettingsScreen(),
      const NotesScreen(),
      const VbbScreen(),
      const BookmarksScreen(),
      const IServScreen(),
    ];
    Tutorial.navigate = MainScreen.navigateTo;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstLaunch();
      _checkForUpdates();
    });
  }

  @override
  void dispose() {
    _pageTransitionController.dispose();
    _menuSlideController.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final updateInfo = await UpdateService.checkForUpdate();
    if (updateInfo != null && mounted) {
      UpdateService.sendUpdateNotification(updateInfo);
      UpdateService.showUpdateDialog(context, updateInfo);
    }
  }

  Future<void> _checkFirstLaunch() async {
    if (_hasCheckedFirstLaunch) return;
    _hasCheckedFirstLaunch = true;

    final prefs = await SharedPreferences.getInstance();
    final hasSelectedBundesland = prefs.containsKey('user_bundesland');

    if (!hasSelectedBundesland && mounted) {
      await _showBundeslandDialog();
    } else if (hasSelectedBundesland) {
      _importHolidaysIfNeeded();
    }
  }

  Future<void> _importHolidaysIfNeeded() async {
    try {
      final holidayService = HolidayService();
      final hasHolidays = await holidayService.hasImportedHolidays();
      if (kDebugMode) print('main.dart: hasImportedHolidays returned $hasHolidays');

      if (!hasHolidays) {
        if (kDebugMode) print('main.dart: Starting holiday import...');
        final events = await holidayService.importHolidays();
        if (kDebugMode) print('main.dart: Holiday import complete, got ${events.length} events');

        if (mounted) {
          if (kDebugMode) print('main.dart: Refreshing AppProvider to reload events...');
          await context.read<AppProvider>().refresh();
          if (kDebugMode) print('main.dart: AppProvider refresh complete');
        }
      } else {
        if (kDebugMode) print('main.dart: Holidays already imported, skipping import');
      }
    } catch (e) {
      if (kDebugMode) print('main.dart: Error in _importHolidaysIfNeeded: $e');
    }
  }

  Future<void> _showBundeslandDialog() async {
    final result = await showDialog<WelcomeSetupResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _WelcomeSetupDialog(bundeslaender: _bundeslaender),
    );

    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_bundesland', result.bundesland);
      await prefs.setInt('graduation_year', result.graduationYear);

      if (result.enableDemo) {
        if (mounted) {
          await context.read<AppProvider>().setDemoMode(true);
        }
      }

      if (mounted) {
        _importHolidaysAfterSelection();
        Future.delayed(const Duration(milliseconds: 700), Tutorial.startIfNew);
      }
    }
  }

  Future<void> _importHolidaysAfterSelection() async {
    try {
      if (kDebugMode) print('main.dart: User selected Bundesland, starting holiday import...');
      final holidayService = HolidayService();
      final events = await holidayService.importHolidays();
      if (kDebugMode) print('main.dart: Holiday import after selection complete, got ${events.length} events');

      if (mounted) {
        if (kDebugMode) print('main.dart: Refreshing AppProvider...');
        context.read<AppProvider>().refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${events.length} Feiertage und Ferien wurden importiert'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) print('main.dart: ERROR importing holidays after selection: $e');
      if (kDebugMode) print('main.dart: Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Importieren der Feiertage. Bitte versuche es erneut.'),
            backgroundColor: AppTheme.warning,
          ),
        );
      }
    }
  }

  bool _hasOwnScaffold(int index) {
    const screensWithScaffold = {12, 13, 14};
    return screensWithScaffold.contains(index);
  }

  Widget _buildScreenStack({required bool isTablet, required bool isDark}) {
    return AnimatedBuilder(
      animation: _pageTransitionController,
      builder: (context, child) {
        final t = _pageTransitionController.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: IndexedStack(
              index: _displayIndex,
              children: [
                for (int i = 0; i < _screens.length; i++)
                  RepaintBoundary(
                    child: _hasOwnScaffold(i)
                        ? _screens[i]
                        : isTablet
                            ? Column(
                                children: [
                                  _buildTabletAppBar(context, isDark),
                                  Expanded(child: _screens[i]),
                                ],
                              )
                            : _screens[i],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isNavigating = false;
  int _displayIndex = 0;

  void _navigateToScreen(int screenIndex) async {
    if (screenIndex == _currentIndex || _isNavigating) return;
    _isNavigating = true;
    _currentIndex = screenIndex;

    _pageTransitionController.stop();
    await _pageTransitionController.animateTo(0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeIn,
    );
    if (!mounted) { _isNavigating = false; return; }

    setState(() => _displayIndex = screenIndex);

    await Future.delayed(const Duration(milliseconds: 32));
    if (!mounted) { _isNavigating = false; return; }

    await _pageTransitionController.animateTo(1,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );

    _isNavigating = false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTablet = Responsive.useTabletLayout(context);

    if (isTablet) {
      return _buildTabletLayout(context, isDark);
    } else {
      return _buildPhoneLayout(context, isDark);
    }
  }

  void _openMobileMenu() {
    setState(() => _isMobileMenuOpen = true);
    _menuSlideController.forward();
  }

  void _closeMobileMenu() {
    _menuSlideController.reverse().then((_) {
      if (mounted) setState(() => _isMobileMenuOpen = false);
    });
  }

  void _navigateFromMenu(int index) {
    _closeMobileMenu();
    Future.delayed(const Duration(milliseconds: 150), () {
      _navigateToScreen(index);
    });
  }

  static const _pillNavItems = [
    (index: 0, icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, label: 'Übersicht'),
    (index: 1, icon: Icons.task_alt_outlined, activeIcon: Icons.task_alt, label: 'Aufgaben'),
    (index: 3, icon: Icons.school_outlined, activeIcon: Icons.school, label: 'Schule'),
    (index: 2, icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today, label: 'Kalender'),
  ];

  static const _menuItems = [
    (index: 0, icon: Icons.dashboard_outlined, label: 'Übersicht', color: AppPalette.iris),
    (index: 1, icon: Icons.task_alt_outlined, label: 'Aufgaben', color: AppPalette.iris),
    (index: 2, icon: Icons.calendar_today_outlined, label: 'Kalender', color: AppPalette.iris),
    (index: 3, icon: Icons.school_outlined, label: 'Schule', color: AppPalette.slate),
    (index: 11, icon: Icons.note_outlined, label: 'Notizen', color: AppPalette.sand),
    (index: 5, icon: Icons.timer_outlined, label: 'Pomodoro', color: AppPalette.ochre),
    (index: 6, icon: Icons.fitness_center_outlined, label: 'Training', color: AppPalette.rose),
    (index: 7, icon: Icons.email_outlined, label: 'E-Mail', color: AppPalette.terracotta),
    (index: 8, icon: Icons.show_chart_outlined, label: 'Review', color: AppPalette.sage),
    (index: 9, icon: Icons.smart_toy_outlined, label: 'Assistent', color: AppPalette.iris),
    (index: 12, icon: Icons.train_outlined, label: 'Fahrplan', color: AppPalette.terracotta),
    (index: 13, icon: Icons.bookmark_outline, label: 'Lesezeichen', color: AppPalette.plum),
    (index: 14, icon: Icons.dns_outlined, label: 'IServ', color: AppPalette.slate),
    (index: 10, icon: Icons.settings_outlined, label: 'Einstellungen', color: AppPalette.ring),
  ];

  Widget _buildPhoneLayout(BuildContext context, bool isDark) {
    return PopScope(
      canPop: !_isMobileMenuOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isMobileMenuOpen) {
          _closeMobileMenu();
        }
      },
      child: AppBackground(
      child: ConnectionIndicator(
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: Builder(
                  builder: (innerContext) {
                    final media = MediaQuery.of(innerContext);
                    final clearance = media.viewInsets.bottom == 0 ? _pillNavClearance : 0.0;
                    return MediaQuery(
                      data: media.copyWith(
                        padding: media.padding.copyWith(bottom: media.padding.bottom + clearance),
                        viewPadding: media.viewPadding.copyWith(bottom: media.viewPadding.bottom + clearance),
                      ),
                      child: _buildScreenStack(isTablet: false, isDark: isDark),
                    );
                  },
                ),
              ),

              if (MediaQuery.of(context).viewInsets.bottom == 0)
                _buildBottomPillNav(isDark),

              if (_isMobileMenuOpen) ...[
                GestureDetector(
                  onTap: _closeMobileMenu,
                  child: AnimatedBuilder(
                    animation: _menuSlideController,
                    builder: (context, child) => Container(
                      color: const Color(0xFF0B120D).withValues(alpha: 0.32 * _menuSlideController.value),
                    ),
                  ),
                ),
                _buildMobileMenuPanel(isDark),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildBottomPillNav(bool isDark) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: MediaQuery.of(context).padding.bottom + 10,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF14201A).withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          key: Tutorial.key('nav'),
          borderRadius: BorderRadius.circular(100),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: (isDark ? AppPalette.overlayDark : AppPalette.overlay).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: isDark ? AppPalette.lineDark : AppPalette.line),
              ),
              child: Row(
                children: [
                  for (final item in _pillNavItems)
                    Expanded(child: _buildPillNavItem(item.index, item.icon, item.activeIcon, item.label, isDark)),
                  Expanded(child: _buildPillMenuButton(isDark)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navTarget({
    required Key key,
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required bool isActive,
    required bool isDark,
  }) {
    final ink = isDark ? AppPalette.inkDark : AppPalette.ink;
    final muted = isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted;
    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        key: key,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: isActive ? (isDark ? AppPalette.hoverDark : AppPalette.press) : Colors.transparent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Icon(icon, size: 22, color: isActive ? ink : muted),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? ink : muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPillNavItem(int index, IconData icon, IconData activeIcon, String label, bool isDark) {
    final isActive = _currentIndex == index;
    return _navTarget(
      key: Tutorial.key('nav-$index'),
      onTap: () => _navigateToScreen(index),
      icon: isActive ? activeIcon : icon,
      label: label,
      isActive: isActive,
      isDark: isDark,
    );
  }

  Widget _buildPillMenuButton(bool isDark) {
    final inMenu = !_pillNavItems.any((item) => item.index == _currentIndex);
    return _navTarget(
      key: Tutorial.key('nav-more'),
      onTap: _openMobileMenu,
      icon: Icons.grid_view_rounded,
      label: 'Mehr',
      isActive: inMenu,
      isDark: isDark,
    );
  }

  Widget _buildMobileMenuPanel(bool isDark) {
    final screenHeight = MediaQuery.of(context).size.height;
    final menuHeight = screenHeight * 0.85;
    final ink = isDark ? AppPalette.inkDark : AppPalette.ink;
    final inkSoft = isDark ? AppPalette.inkSoftDark : AppPalette.inkSoft;
    final line = isDark ? AppPalette.lineDark : AppPalette.line;

    return AnimatedBuilder(
      animation: _menuSlideController,
      builder: (context, child) {
        final slideValue = Curves.easeOutCubic.transform(_menuSlideController.value);
        return Positioned(
          left: 0,
          right: 0,
          bottom: -(menuHeight * (1.0 - slideValue)),
          height: menuHeight,
          child: child!,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppPalette.overlayDark : AppPalette.overlay,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: line)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppPalette.lineStrongDark : AppPalette.lineStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  Image.asset('assets/logo.png', width: 28, height: 28),
                  const SizedBox(width: 10),
                  Text(
                    Brand.name,
                    style: TextStyle(fontFamily: AppTheme.fontFamily, color: ink, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _closeMobileMenu,
                    tooltip: 'Schließen',
                    icon: Icon(Icons.close_rounded, size: 22, color: inkSoft),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 2.6,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _menuItems.length,
                itemBuilder: (context, i) {
                  final item = _menuItems[i];
                  final isActive = _currentIndex == item.index;
                  return Material(
                    color: isActive ? (isDark ? AppPalette.hoverDark : AppPalette.press) : (isDark ? AppPalette.surfaceDark : AppPalette.surface),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: isActive ? Colors.transparent : line),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _navigateFromMenu(item.index),
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          Icon(item.icon, size: 20, color: isActive ? ink : inkSoft),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 15,
                                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                                color: ink,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context, bool isDark) {
    final sidebarWidth = Responsive.getSidebarWidth(context);

    return AppBackground(
      child: ConnectionIndicator(
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Row(
              children: [
                _buildTabletSidebar(context, isDark, sidebarWidth),
                Expanded(
                  child: _buildScreenStack(isTablet: true, isDark: isDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabletSidebar(BuildContext context, bool isDark, double width) {
    final ink = isDark ? AppPalette.inkDark : AppPalette.ink;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B100C) : AppPalette.sunken,
        border: Border(right: BorderSide(color: isDark ? AppPalette.lineDark : AppPalette.line)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(
              children: [
                Image.asset('assets/logo.png', width: 30, height: 30, fit: BoxFit.contain),
                const SizedBox(width: 10),
                Text(
                  Brand.name,
                  style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: ink),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Stack(
                children: [
                  if (_sidebarOrder.contains(_currentIndex))
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 320),
                      curve: const Cubic(0.23, 1, 0.32, 1),
                      left: 0,
                      right: 0,
                      top: _sidebarOrder.indexOf(_currentIndex) * _sidebarItemHeight,
                      height: _sidebarItemHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: isDark ? AppPalette.hoverDark : AppPalette.press,
                        ),
                      ),
                    ),
                  Column(
                    key: Tutorial.key('nav'),
                    children: [
                      _buildTabletNavItem(0, Icons.dashboard_outlined, 'Übersicht', isDark),
                      _buildTabletNavItem(1, Icons.task_alt_outlined, 'Aufgaben', isDark),
                      _buildTabletNavItem(2, Icons.calendar_today_outlined, 'Kalender', isDark),
                      _buildTabletNavItem(3, Icons.school_outlined, 'Schule', isDark),
                      _buildTabletNavItem(6, Icons.fitness_center_outlined, 'Training', isDark),
                      _buildTabletNavItem(8, Icons.show_chart_outlined, 'Review', isDark),
                      _buildTabletNavItem(11, Icons.note_outlined, 'Notizen', isDark),
                      _buildTabletNavItem(13, Icons.bookmark_outline, 'Lesezeichen', isDark),
                      _buildTabletNavItem(7, Icons.email_outlined, 'E-Mail', isDark),
                      _buildTabletNavItem(12, Icons.train_outlined, 'Fahrplan', isDark),
                      _buildTabletNavItem(5, Icons.timer_outlined, 'Pomodoro', isDark),
                      _buildTabletNavItem(14, Icons.dns_outlined, 'IServ', isDark),
                      _buildTabletNavItem(9, Icons.smart_toy_outlined, 'Assistent', isDark),
                      _buildTabletNavItem(10, Icons.settings_outlined, 'Einstellungen', isDark),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletNavItem(int index, IconData icon, String label, bool isDark) {
    final isActive = _currentIndex == index;
    final color = isActive ? (isDark ? AppPalette.inkDark : AppPalette.ink) : (isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted);
    return GestureDetector(
      key: Tutorial.key('nav-$index'),
      onTap: () => _navigateToScreen(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: _sidebarItemHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 15,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabletAppBar(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      child: Row(
        children: [
          AppTheme.gradientText(_getScreenTitle(_currentIndex), fontSize: 28),
          const Spacer(),
        ],
      ),
    );
  }

  String _getScreenTitle(int index) {
    switch (index) {
      case 0: return 'Übersicht';
      case 1: return 'Aufgaben';
      case 2: return 'Kalender';
      case 3: return 'Schule';
      case 4: return 'Mehr';
      case 5: return 'Pomodoro';
      case 6: return 'Training';
      case 7: return 'E-Mail';
      case 8: return 'Review';
      case 9: return 'Assistent';
      case 10: return 'Einstellungen';
      case 11: return 'Notizen';
      case 12: return 'Fahrplan';
      case 13: return 'Lesezeichen';
      case 14: return 'IServ';
      default: return '';
    }
  }

}

Future<WelcomeSetupResult?> showWelcomeSetup(BuildContext context, {bool withDemo = true}) {
  return showDialog<WelcomeSetupResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _WelcomeSetupDialog(bundeslaender: _MainScreenState._bundeslaender, withDemo: withDemo),
  );
}

class WelcomeSetupResult {
  final String bundesland;
  final int graduationYear;
  final bool enableDemo;

  WelcomeSetupResult({required this.bundesland, required this.graduationYear, this.enableDemo = false});
}

class _WelcomeSetupDialog extends StatefulWidget {
  final List<String> bundeslaender;
  final bool withDemo;

  const _WelcomeSetupDialog({required this.bundeslaender, this.withDemo = true});

  @override
  State<_WelcomeSetupDialog> createState() => _WelcomeSetupDialogState();
}

class _WelcomeSetupDialogState extends State<_WelcomeSetupDialog>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  String? _selectedBundesland;
  int? _selectedGraduationYear;
  bool _enableDemo = false;
  late AnimationController _animationController;

  int get _lastStep => widget.withDemo ? 2 : 1;
  late Animation<double> _fadeAnimation;

  List<int> get _graduationYears {
    final currentYear = DateTime.now().year;
    return List.generate(11, (i) => currentYear + i);
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 620),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: isDark ? AppPalette.overlayDark : AppPalette.overlay,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? AppPalette.lineDark : AppPalette.line),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withValues(alpha: .5) : const Color(0xFF14201A).withValues(alpha: .18),
                blurRadius: 36,
                spreadRadius: -10,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(isDark),
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                  child: _currentStep == 0
                      ? _buildBundeslandStep(isDark)
                      : _currentStep == 1
                          ? _buildGraduationStep(isDark)
                          : _buildDemoStep(isDark),
                ),
              ),
              _buildFooter(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      color: isDark ? AppPalette.heroDark : AppPalette.pine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppPalette.chalk.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _currentStep == 0 ? Icons.map_outlined : _currentStep == 1 ? Icons.school_outlined : Icons.science_outlined,
                  color: AppPalette.chalk,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Willkommen!',
                      style: TextStyle(color: AppPalette.chalk, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _currentStep == 0
                          ? 'Wo bist du zuhause?'
                          : _currentStep == 1
                              ? 'Wie lange noch?'
                              : 'Erstmal ausprobieren?',
                      style: TextStyle(color: AppPalette.chalk.withValues(alpha: .8), fontSize: 15),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _buildStepPill(0, 'Bundesland'),
              const SizedBox(width: 6),
              _buildStepPill(1, 'Abschluss'),
              if (widget.withDemo) ...[
                const SizedBox(width: 6),
                _buildStepPill(2, 'Demo'),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepPill(int step, String label) {
    final isDone = _currentStep > step;
    final isCurrent = _currentStep == step;
    final isActive = isDone || isCurrent;

    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
        decoration: BoxDecoration(
          color: AppPalette.chalk.withValues(alpha: isCurrent ? .16 : isDone ? .08 : 0),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppPalette.chalk.withValues(alpha: isCurrent ? .4 : .16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? AppPalette.chalk : AppPalette.chalk.withValues(alpha: .2),
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check, color: AppPalette.pine, size: 12)
                    : Text(
                        '${step + 1}',
                        style: TextStyle(
                          color: isActive ? AppPalette.pine : AppPalette.chalk,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  color: AppPalette.chalk.withValues(alpha: isActive ? 1 : .7),
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _note(bool isDark, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppPalette.hoverDark : AppPalette.sunken,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, height: 1.35, color: isDark ? AppPalette.inkSoftDark : AppPalette.inkSoft),
            ),
          ),
        ],
      ),
    );
  }

  Widget _choiceIcon(bool isDark, bool selected, Widget Function(Color color) child, {double size = 44}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? AppTheme.primaryColor : (isDark ? AppPalette.hoverDark : AppPalette.sunken),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: child(selected ? (isDark ? Colors.white : AppPalette.chalk) : (isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted)),
      ),
    );
  }

  Widget _choice({
    required bool isDark,
    required bool selected,
    required VoidCallback onTap,
    required Widget leading,
    required String title,
    String? subtitle,
    double padding = 12,
    double gap = 8,
  }) {
    final surface = isDark ? AppPalette.surfaceDark : AppPalette.surface;
    final accent = AppTheme.primaryColor;
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: selected ? Color.alphaBlend(accent.withValues(alpha: isDark ? .16 : .06), surface) : surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? accent : (isDark ? AppPalette.lineDark : AppPalette.line),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected
                              ? (isDark ? AppPalette.inkDark : AppPalette.ink)
                              : (isDark ? AppPalette.inkSoftDark : AppPalette.inkSoft),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 12, color: isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    child: Icon(Icons.check, color: isDark ? Colors.white : AppPalette.chalk, size: 15),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBundeslandStep(bool isDark) {
    return Padding(
      key: const ValueKey('bundesland'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _note(isDark, Icons.info_outline, 'Wird verwendet, um Ferien und Feiertage zu importieren'),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: widget.bundeslaender.length,
              itemBuilder: (context, index) {
                final bundesland = widget.bundeslaender[index];
                final isSelected = _selectedBundesland == bundesland;
                return _choice(
                  isDark: isDark,
                  selected: isSelected,
                  onTap: () => setState(() => _selectedBundesland = bundesland),
                  leading: _choiceIcon(isDark, isSelected, (c) => Icon(Icons.location_on_outlined, size: 20, color: c), size: 40),
                  title: bundesland,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraduationStep(bool isDark) {
    return Padding(
      key: const ValueKey('graduation'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _note(isDark, Icons.auto_awesome, 'Ferien werden automatisch bis zu diesem Jahr importiert'),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _graduationYears.length,
              itemBuilder: (context, index) {
                final year = _graduationYears[index];
                final isSelected = _selectedGraduationYear == year;
                final yearsFromNow = year - DateTime.now().year;
                final label = yearsFromNow == 0
                    ? 'Dieses Jahr'
                    : yearsFromNow == 1
                        ? 'In einem Jahr'
                        : 'In $yearsFromNow Jahren';
                return _choice(
                  isDark: isDark,
                  selected: isSelected,
                  onTap: () => setState(() => _selectedGraduationYear = year),
                  leading: _choiceIcon(
                    isDark,
                    isSelected,
                    (c) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.school_rounded, size: 18, color: c),
                        const SizedBox(height: 1),
                        Text('$year', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
                      ],
                    ),
                    size: 48,
                  ),
                  title: 'Abschluss $year',
                  subtitle: label,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoStep(bool isDark) {
    final options = [
      (title: 'Mit Beispieldaten starten', subtitle: 'Erkunde ${Brand.name} mit vorausgefüllten Daten', icon: Icons.play_circle_outline, value: true),
      (title: 'Direkt loslegen', subtitle: 'Starte mit einem leeren Arbeitsbereich', icon: Icons.rocket_launch_outlined, value: false),
    ];
    return Padding(
      key: const ValueKey('demo'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _note(isDark, Icons.info_outline, 'Du kannst den Demo-Modus jederzeit in den Einstellungen ändern'),
          const SizedBox(height: 16),
          for (final option in options)
            _choice(
              isDark: isDark,
              selected: _enableDemo == option.value,
              onTap: () => setState(() => _enableDemo = option.value),
              leading: _choiceIcon(isDark, _enableDemo == option.value, (c) => Icon(option.icon, size: 22, color: c)),
              title: option.title,
              subtitle: option.subtitle,
              padding: 14,
              gap: 10,
            ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isDark) {
    final ink = isDark ? AppPalette.inkDark : AppPalette.ink;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: isDark ? AppPalette.lineDark : AppPalette.line)),
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _currentStep = _currentStep - 1),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Zurück'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: isDark ? AppPalette.lineStrongDark : AppPalette.lineStrong),
                  shape: const StadiumBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _canProceed() ? _handleNext : null,
              icon: Icon(_currentStep < _lastStep ? Icons.arrow_forward : Icons.check, size: 18),
              label: Text(_currentStep < _lastStep ? 'Weiter' : 'Los geht\'s'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? AppPalette.brandDark : AppPalette.pine,
                foregroundColor: isDark ? AppPalette.inkDark : AppPalette.chalk,
                disabledBackgroundColor: isDark ? AppPalette.lineDark : AppPalette.lineStrong,
                disabledForegroundColor: isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted,
                elevation: 0,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: StadiumBorder(
                  side: isDark && _canProceed() ? const BorderSide(color: Color(0xFF3E5541)) : BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _canProceed() {
    if (_currentStep == 0) {
      return _selectedBundesland != null;
    } else if (_currentStep == 1) {
      return _selectedGraduationYear != null;
    } else {
      return true;
    }
  }

  void _handleNext() {
    if (_currentStep < _lastStep) {
      setState(() => _currentStep = _currentStep + 1);
    } else {
      Navigator.pop(
        context,
        WelcomeSetupResult(
          bundesland: _selectedBundesland!,
          graduationYear: _selectedGraduationYear!,
          enableDemo: _enableDemo,
        ),
      );
    }
  }
}

class _AppInitializer extends StatefulWidget {
  final Widget Function(BuildContext context) builder;
  const _AppInitializer({required this.builder});

  @override
  State<_AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<_AppInitializer>
    with TickerProviderStateMixin {
  bool _initialized = false;

  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _fadeOutController;

  @override
  void initState() {
    super.initState();
    debugPrint('=== LOADING SCREEN BUILD ${BuildInfo.buildNumber} ===');

    _logoController = AnimationController(
      duration: const Duration(milliseconds: 420),
      vsync: this,
    );
    _textController = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
    );
    _fadeOutController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _logoController.forward();
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) _textController.forward();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeProviders();
    });
  }

  Future<void> _initializeProviders() async {
    final appProvider = context.read<AppProvider>();
    final iservProvider = context.read<IServProvider>();

    try {
      await appProvider.initialize().timeout(const Duration(seconds: 5));
    } catch (_) {
    }
    if (!mounted) return;

    try {
      await iservProvider.initialize().timeout(const Duration(seconds: 10));
    } catch (_) {
      // Don't block app startup if IServ init fails or times out
    }

    if (mounted) {
      await _fadeOutController.forward();
      if (mounted) {
        setState(() => _initialized = true);
      }
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initialized) {
      return widget.builder(context);
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: FadeTransition(
        opacity: Tween<double>(begin: 1.0, end: 0.0).animate(
          CurvedAnimation(parent: _fadeOutController, curve: Curves.easeOut),
        ),
        child: Builder(builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final ink = isDark ? AppPalette.inkDark : AppPalette.ink;
          return AppBackground(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _logoController,
                      builder: (context, child) {
                        final k = Curves.easeOutCubic.transform(_logoController.value);
                        return Opacity(
                          opacity: k,
                          child: Transform.scale(scale: .96 + .04 * k, child: child),
                        );
                      },
                      child: Image.asset('assets/logo.png', width: 88, height: 88, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 20),
                    AnimatedBuilder(
                      animation: _textController,
                      builder: (context, child) {
                        final k = Curves.easeOutCubic.transform(_textController.value);
                        return Opacity(
                          opacity: k,
                          child: Transform.translate(offset: Offset(0, 6 * (1 - k)), child: child),
                        );
                      },
                      child: Text(
                        Brand.name,
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          color: ink,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    FadeTransition(
                      opacity: _textController,
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isDark ? AppPalette.sageDark : AppPalette.sage,
                          backgroundColor: isDark ? AppPalette.lineDark : AppPalette.line,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}


