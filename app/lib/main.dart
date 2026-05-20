import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ✅ Added 'hide AppColors, ApiConfig' to prevent the ambiguous import error!
import 'screens/monitor_screen.dart' hide AppColors, ApiConfig;
import 'screens/incidents_screen.dart';
import 'screens/agent_screen.dart' hide AppColors, ApiConfig;
import 'services/alert_service.dart';
import 'theme/app_colors.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CIRO Fire Crisis Response',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          surface: AppColors.surface,
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  bool _testModeEnabled = false;

  final List<Widget> _screens = [
    const MonitorScreen(),
    const IncidentsScreen(),
    const AgentTracesScreen(),
  ];

  @override
  void initState() {
    super.initState();
    final alertService = AlertService();
    alertService.onAlertReceived = (data) {
      if (!mounted) return;
      final type = data['type'] ?? 'ALERT';
      final message = data['message'] ?? 'An alert was received.';
      final confidence = data['confidence'] ?? 0.0;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$type (Conf: ${(confidence * 100).toStringAsFixed(0)}%)',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                    ),
                    Text(message, style: GoogleFonts.outfit()),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    };
    alertService.connect();
  }

  void _simulateEvent() {
    if (!_testModeEnabled) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Test Mode: Simulated event triggered',
          style: GoogleFonts.outfit(),
        ),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> _titles = [
      'CIRO Operations',
      'Incident Logs',
      'Agent Traces',
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _titles[_currentIndex],
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        elevation: 0,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: AlertService().isConnected,
            builder: (context, isConnected, child) {
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Row(
                  children: [
                    Icon(
                      isConnected ? Icons.wifi : Icons.wifi_off,
                      color: isConnected ? Colors.greenAccent : Colors.white70,
                      size: 20,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: AppColors.surface,
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                gradient: AppColors.cyberGradient,
              ),
              accountName: Text(
                'Commander Steve Musk',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              accountEmail: Text(
                'commander@ciro.ai',
                style: GoogleFonts.outfit(color: Colors.white70),
              ),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: AppColors.primary, size: 40),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.settings,
                      color: AppColors.textSecondary,
                    ),
                    title: Text(
                      'Settings',
                      style: GoogleFonts.outfit(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {},
                  ),
                  SwitchListTile(
                    title: Text(
                      'Test Mode',
                      style: GoogleFonts.outfit(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'Enable simulated events',
                      style: GoogleFonts.outfit(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    activeColor: AppColors.primary,
                    value: _testModeEnabled,
                    onChanged: (val) {
                      setState(() {
                        _testModeEnabled = val;
                      });
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.info_outline,
                      color: AppColors.textSecondary,
                    ),
                    title: Text(
                      'About CIRO',
                      style: GoogleFonts.outfit(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: Text(
                'Logout',
                style: GoogleFonts.outfit(
                  color: AppColors.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () {},
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        selectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.normal),
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        elevation: 10,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Monitor',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'Incidents',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.memory_outlined),
            activeIcon: Icon(Icons.memory),
            label: 'Agent',
          ),
        ],
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
      floatingActionButton: _testModeEnabled
          ? FloatingActionButton(
              onPressed: _simulateEvent,
              backgroundColor:
                  AppColors.warning, // ✅ Fixed the syntax error here!
              child: const Icon(Icons.bug_report, color: Colors.white),
              tooltip: 'Simulate Event',
            )
          : null,
    );
  }
}
