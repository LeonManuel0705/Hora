// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:math' as math;
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Hive.initFlutter().timeout(const Duration(seconds: 5));
  } catch (_) {
  }

  try {
    await initializeDateFormatting('de_DE', null);
  } catch (_) {
  }

  try {
    await ConnectivityService().initialize();
  } catch (_) {
  }

  try {
    await OfflineQueue().initialize();
  } catch (_) {
  }

  try {
    await CalendarSyncService().initialize();
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

    try {
      await NotificationService().initialize();
    } catch (_) {
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
            final isDark = provider.themeMode == ThemeMode.dark;
            if (!kIsWeb) {
              SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
                systemNavigationBarColor: isDark ? const Color(0xFF14131A) : const Color(0xFFFBFAFF),
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
              builder: (context, child) => TutorialHost(child: child ?? const SizedBox.shrink()),
              home: (!kIsWeb && isDesktopPlatform())
                  ? buildDesktopHome()
                  : MainScreen(key: MainScreen._globalKey),
            );
          },
        ),
      ),
    );
  }
}

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
            backgroundColor: Colors.green,
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
            backgroundColor: Colors.orange,
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
    (index: 0, icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, label: 'Home'),
    (index: 1, icon: Icons.task_alt_outlined, activeIcon: Icons.task_alt, label: 'Aufgaben'),
    (index: 3, icon: Icons.school_outlined, activeIcon: Icons.school, label: 'Schule'),
    (index: 2, icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today, label: 'Kalender'),
  ];

  static const _menuItems = [
    (index: 0, icon: Icons.dashboard_outlined, label: 'Dashboard', color: Color(0xFF6366F1)),
    (index: 1, icon: Icons.task_alt_outlined, label: 'Aufgaben', color: Color(0xFF6366F1)),
    (index: 2, icon: Icons.calendar_today_outlined, label: 'Kalender', color: Color(0xFF6366F1)),
    (index: 3, icon: Icons.school_outlined, label: 'Schule', color: Color(0xFF3B82F6)),
    (index: 11, icon: Icons.note_outlined, label: 'Notizen', color: Color(0xFFFACC15)),
    (index: 5, icon: Icons.timer_outlined, label: 'Pomodoro', color: Color(0xFFF97316)),
    (index: 6, icon: Icons.fitness_center_outlined, label: 'Training', color: Color(0xFFEC4899)),
    (index: 7, icon: Icons.email_outlined, label: 'E-Mail', color: Color(0xFFEF4444)),
    (index: 8, icon: Icons.show_chart_outlined, label: 'Review', color: Color(0xFF10B981)),
    (index: 9, icon: Icons.smart_toy_outlined, label: 'Assistent', color: Color(0xFF6366F1)),
    (index: 12, icon: Icons.train_outlined, label: 'Fahrplan', color: Color(0xFFEF4444)),
    (index: 13, icon: Icons.bookmark_outline, label: 'Lesezeichen', color: Color(0xFF8B5CF6)),
    (index: 14, icon: Icons.dns_outlined, label: 'IServ', color: Color(0xFF3B82F6)),
    (index: 10, icon: Icons.settings_outlined, label: 'Einstellungen', color: Color(0xFF71717A)),
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
                      color: Colors.black.withValues(alpha: 0.3 * _menuSlideController.value),
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
      left: 16,
      right: 16,
      bottom: MediaQuery.of(context).padding.bottom + 12,
      child: ClipRRect(
        key: Tutorial.key('nav'),
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF18181B).withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.05),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final item in _pillNavItems)
                  _buildPillNavItem(item.index, item.icon, item.activeIcon, item.label, isDark),
                _buildPillMenuButton(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPillNavItem(int index, IconData icon, IconData activeIcon, String label, bool isDark) {
    final isActive = _currentIndex == index;

    return GestureDetector(
      key: Tutorial.key('nav-$index'),
      onTap: () => _navigateToScreen(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isActive
                    ? (isDark ? const Color(0xFF7353CD).withValues(alpha: 0.22) : const Color(0xFFEAE7FF))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isActive ? activeIcon : icon,
                size: isActive ? 24 : 22,
                color: isActive
                    ? (isDark ? const Color(0xFFB7A6F6) : const Color(0xFF7353CD))
                    : (isDark ? const Color(0xFF9E9DAA) : const Color(0xFF686775)),
              ),
            ),
            if (!isActive)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: isDark ? const Color(0xFF71717A) : const Color(0xFF71717A),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPillMenuButton(bool isDark) {
    return GestureDetector(
      key: Tutorial.key('nav-more'),
      onTap: _openMobileMenu,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.grid_view_rounded,
              size: 22,
              color: isDark ? const Color(0xFF71717A) : const Color(0xFF71717A),
            ),
            const SizedBox(height: 2),
            Text(
              'Mehr',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFF71717A) : const Color(0xFF71717A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileMenuPanel(bool isDark) {
    final screenHeight = MediaQuery.of(context).size.height;
    final menuHeight = screenHeight * 0.85;

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
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF18181B).withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.55),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.30),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset('assets/logo.png', width: 32, height: 32),
                    ),
                    const SizedBox(width: 12),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: AppTheme.primaryGradient,
                      ).createShader(bounds),
                      child: const Text(
                        Brand.name,
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _closeMobileMenu,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.close,
                          size: 20,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 2.2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _menuItems.length,
                  itemBuilder: (context, i) {
                    final item = _menuItems[i];
                    final isActive = _currentIndex == item.index;
                    return GestureDetector(
                      onTap: () => _navigateFromMenu(item.index),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isActive
                              ? item.color.withValues(alpha: isDark ? 0.15 : 0.1)
                              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isActive
                                ? item.color.withValues(alpha: 0.3)
                                : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 14),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: item.color.withValues(alpha: isDark ? 0.2 : 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(item.icon, size: 20, color: item.color),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                                  color: isActive
                                      ? item.color
                                      : (isDark ? Colors.white : const Color(0xFF18181B)),
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
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF14131A).withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.55),
            border: Border(
              right: BorderSide(
                color: isDark
                    ? const Color(0xFF27272A)
                    : const Color(0xFFE4E4E7),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                blurRadius: 12,
                offset: const Offset(2, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/logo.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      Brand.name,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                        color: isDark ? Colors.white : const Color(0xFF18181B),
                      ),
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
                          duration: const Duration(milliseconds: 600),
                          curve: const Cubic(0.34, 1.56, 0.64, 1),
                          left: 0,
                          right: 0,
                          top: _sidebarOrder.indexOf(_currentIndex) * _sidebarItemHeight,
                          height: _sidebarItemHeight,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFE1EEF1),
                                  Color(0xFFC9DAF8),
                                  Color(0xFFB2C6FE),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Column(
                        key: Tutorial.key('nav'),
                        children: [
                          _buildTabletNavItem(0, Icons.dashboard_outlined, 'Dashboard', isDark),
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
        ),
      ),
    );
  }

  Widget _buildTabletNavItem(int index, IconData icon, String label, bool isDark) {
    final isActive = _currentIndex == index;
    const activeColor = Color(0xFF1E3A8A);
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
              Icon(
                icon,
                size: isActive ? 18 : 16,
                color: isActive
                    ? activeColor
                    : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive
                        ? activeColor
                        : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B)),
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
      case 0: return 'Dashboard';
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

class WelcomeSetupResult {
  final String bundesland;
  final int graduationYear;
  final bool enableDemo;

  WelcomeSetupResult({required this.bundesland, required this.graduationYear, this.enableDemo = false});
}

class _WelcomeSetupDialog extends StatefulWidget {
  final List<String> bundeslaender;

  const _WelcomeSetupDialog({required this.bundeslaender});

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
  late Animation<double> _fadeAnimation;

  static const _cardGradients = [
    [Color(0xFF667EEA), Color(0xFF764BA2)],
    [Color(0xFF9580E8), Color(0xFFF5576C)],
    [Color(0xFF4FACFE), Color(0xFF00F2FE)],
    [Color(0xFF43E97B), Color(0xFF38F9D7)],
    [Color(0xFFFA709A), Color(0xFFFEE140)],
    [Color(0xFF30CFD0), Color(0xFF330867)],
    [Color(0xFFA8EDEA), Color(0xFFFED6E3)],
    [Color(0xFFFF9A9E), Color(0xFFFECFEF)],
  ];

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
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 620),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [const Color(0xFF1A1A2E), const Color(0xFF16162A)]
                  : [Colors.white, const Color(0xFFF8F9FC)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.3),
                blurRadius: 30,
                spreadRadius: -5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGradientHeader(isDark),
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.1, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
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

  Widget _buildGradientHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppTheme.primaryGradient,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          Positioned(
            left: -10,
            bottom: -30,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      _currentStep == 0 ? Icons.map_outlined : _currentStep == 1 ? Icons.school_outlined : Icons.science_outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Willkommen!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _currentStep == 0
                              ? 'Wo bist du zuhause?'
                              : _currentStep == 1
                                  ? 'Wie lange noch?'
                                  : 'Erstmal ausprobieren?',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _buildModernStepPill(0, 'Bundesland'),
                  const SizedBox(width: 8),
                  _buildModernStepPill(1, 'Abschluss'),
                  const SizedBox(width: 8),
                  _buildModernStepPill(2, 'Demo'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernStepPill(int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;

    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: isCurrent ? 0.3 : 0.15)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCurrent ? Colors.white.withValues(alpha: 0.5) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.3),
              ),
              child: Center(
                child: _currentStep > step
                    ? const Icon(Icons.check, color: AppTheme.primaryColor, size: 14)
                    : Text(
                        '${step + 1}',
                        style: TextStyle(
                          color: isActive ? AppTheme.primaryColor : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: isActive ? 1.0 : 0.7),
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor.withValues(alpha: 0.1),
                  AppTheme.primaryLight.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: AppTheme.primaryColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Wird verwendet um Ferien und Feiertage zu importieren',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: widget.bundeslaender.length,
              itemBuilder: (context, index) {
                final bundesland = widget.bundeslaender[index];
                final isSelected = _selectedBundesland == bundesland;
                final gradientColors = _cardGradients[index % _cardGradients.length];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _selectedBundesland = bundesland),
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    gradientColors[0].withValues(alpha: 0.2),
                                    gradientColors[1].withValues(alpha: 0.1),
                                  ],
                                )
                              : null,
                          color: isSelected
                              ? null
                              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? gradientColors[0].withValues(alpha: 0.5)
                                : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: isSelected
                                    ? LinearGradient(colors: gradientColors)
                                    : null,
                                color: isSelected
                                    ? null
                                    : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.location_on_outlined,
                                  size: 22,
                                  color: isSelected ? Colors.white : (isDark ? Colors.white54 : Colors.black38),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                bundesland,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  fontSize: 15,
                                  color: isSelected
                                      ? (isDark ? Colors.white : gradientColors[0])
                                      : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            ),
                            if (isSelected)
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: gradientColors),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check, color: Colors.white, size: 16),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF43E97B).withValues(alpha: 0.15),
                  const Color(0xFF38F9D7).withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF43E97B)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ferien werden automatisch bis zu diesem Jahr importiert',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
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

                final gradientColors = yearsFromNow <= 2
                    ? [const Color(0xFF43E97B), const Color(0xFF38F9D7)]
                    : yearsFromNow <= 5
                        ? [const Color(0xFF4FACFE), const Color(0xFF00F2FE)]
                        : [const Color(0xFF667EEA), const Color(0xFF764BA2)];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _selectedGraduationYear = year),
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    gradientColors[0].withValues(alpha: 0.2),
                                    gradientColors[1].withValues(alpha: 0.1),
                                  ],
                                )
                              : null,
                          color: isSelected
                              ? null
                              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? gradientColors[0].withValues(alpha: 0.5)
                                : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: isSelected
                                    ? LinearGradient(colors: gradientColors)
                                    : null,
                                color: isSelected
                                    ? null
                                    : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.school_rounded,
                                      size: 20,
                                      color: isSelected ? Colors.white : (isDark ? Colors.white54 : Colors.black38),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$year',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? Colors.white : (isDark ? Colors.white54 : Colors.black38),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Abschluss $year',
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                      fontSize: 15,
                                      color: isSelected
                                          ? (isDark ? Colors.white : gradientColors[0])
                                          : (isDark ? Colors.white70 : Colors.black87),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white38 : Colors.black38,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: gradientColors),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check, color: Colors.white, size: 16),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoStep(bool isDark) {
    return Padding(
      key: const ValueKey('demo'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF4FACFE).withValues(alpha: 0.15),
                  const Color(0xFF00F2FE).withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: Color(0xFF4FACFE)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Du kannst den Demo-Modus jederzeit in den Einstellungen ändern',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...[
            {'title': 'Mit Beispieldaten starten', 'subtitle': 'Erkunde ${Brand.name} mit vorausgefüllten Daten', 'icon': Icons.play_circle_outline, 'value': true, 'colors': [const Color(0xFF4FACFE), const Color(0xFF00F2FE)]},
            {'title': 'Direkt loslegen', 'subtitle': 'Starte mit einem leeren Arbeitsbereich', 'icon': Icons.rocket_launch_outlined, 'value': false, 'colors': [const Color(0xFF43E97B), const Color(0xFF38F9D7)]},
          ].map((option) {
            final isSelected = _enableDemo == (option['value'] as bool);
            final gradientColors = option['colors'] as List<Color>;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _enableDemo = option['value'] as bool),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                gradientColors[0].withValues(alpha: 0.2),
                                gradientColors[1].withValues(alpha: 0.1),
                              ],
                            )
                          : null,
                      color: isSelected
                          ? null
                          : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? gradientColors[0].withValues(alpha: 0.5)
                            : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? LinearGradient(colors: gradientColors)
                                : null,
                            color: isSelected
                                ? null
                                : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            option['icon'] as IconData,
                            size: 24,
                            color: isSelected ? Colors.white : (isDark ? Colors.white54 : Colors.black38),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                option['title'] as String,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  fontSize: 15,
                                  color: isSelected
                                      ? (isDark ? Colors.white : gradientColors[0])
                                      : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                option['subtitle'] as String,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: gradientColors),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, color: Colors.white, size: 16),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _currentStep = _currentStep - 1),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Zurück'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(
                    color: isDark ? Colors.white24 : Colors.black12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            flex: _currentStep > 0 ? 1 : 1,
            child: Container(
              decoration: BoxDecoration(
                gradient: _canProceed()
                    ? const LinearGradient(colors: AppTheme.primaryGradient)
                    : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton.icon(
                onPressed: _canProceed() ? _handleNext : null,
                icon: Icon(
                  _currentStep < 2 ? Icons.arrow_forward : Icons.check,
                  size: 18,
                ),
                label: Text(_currentStep < 2 ? 'Weiter' : 'Los geht\'s'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canProceed() ? Colors.transparent : null,
                  disabledBackgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
    if (_currentStep == 0) {
      setState(() => _currentStep = 1);
    } else if (_currentStep == 1) {
      setState(() => _currentStep = 2);
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
  late AnimationController _ringController;
  late AnimationController _glowController;
  late AnimationController _fadeOutController;

  @override
  void initState() {
    super.initState();
    debugPrint('=== LOADING SCREEN BUILD ${BuildInfo.buildNumber} ===');

    _logoController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _textController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _ringController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat();
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _fadeOutController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _logoController.forward();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _textController.forward();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeProviders();
    });
  }

  Future<void> _initializeProviders() async {
    final appProvider = context.read<AppProvider>();
    final iservProvider = context.read<IServProvider>();

    await appProvider.initialize();
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
    _ringController.dispose();
    _glowController.dispose();
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
      themeMode: ThemeMode.dark,
      home: FadeTransition(
        opacity: Tween<double>(begin: 1.0, end: 0.0).animate(
          CurvedAnimation(parent: _fadeOutController, curve: Curves.easeOut),
        ),
        child: AppBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: Listenable.merge([_logoController, _glowController]),
                    builder: (context, child) {
                      final logoScale = Curves.elasticOut.transform(
                        _logoController.value.clamp(0.0, 1.0),
                      );
                      final logoOpacity = Curves.easeIn.transform(
                        (_logoController.value * 2.5).clamp(0.0, 1.0),
                      );
                      final glowIntensity = 0.15 + 0.25 * _glowController.value;

                      return Opacity(
                        opacity: logoOpacity,
                        child: Transform.scale(
                          scale: logoScale,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryColor
                                      .withValues(alpha: glowIntensity),
                                  blurRadius: 50,
                                  spreadRadius: 15,
                                ),
                                BoxShadow(
                                  color: AppTheme.accentColor
                                      .withValues(alpha: glowIntensity * 0.4),
                                  blurRadius: 80,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(26),
                              child: Image.asset(
                                'assets/logo.png',
                                width: 100,
                                height: 100,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 36),

                  AnimatedBuilder(
                    animation: _textController,
                    builder: (context, child) {
                      final opacity = Curves.easeIn.transform(
                        _textController.value,
                      );
                      final slideY = 20.0 * (1.0 - Curves.easeOutCubic.transform(
                        _textController.value,
                      ));

                      return Opacity(
                        opacity: opacity,
                        child: Transform.translate(
                          offset: Offset(0, slideY),
                          child: ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: AppTheme.primaryGradient,
                            ).createShader(bounds),
                            child: const Text(
                              Brand.name,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 6,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 48),

                  AnimatedBuilder(
                    animation: Listenable.merge([_textController, _ringController]),
                    builder: (context, child) {
                      final opacity = Curves.easeIn.transform(
                        _textController.value,
                      );
                      return Opacity(
                        opacity: opacity,
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: CustomPaint(
                            painter: _GradientRingPainter(
                              progress: _ringController.value,
                              colors: AppTheme.primaryGradient,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientRingPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;

  _GradientRingPainter({required this.progress, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, radius, bgPaint);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final rotation = progress * 2 * math.pi;
    final sweepGradient = SweepGradient(
      colors: [...colors, colors.first.withValues(alpha: 0)],
      stops: const [0.0, 0.35, 0.7, 1.0],
      transform: GradientRotation(rotation),
    );

    final arcPaint = Paint()
      ..shader = sweepGradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, rotation, math.pi * 1.4, false, arcPaint);
  }

  @override
  bool shouldRepaint(_GradientRingPainter old) => old.progress != progress;
}

