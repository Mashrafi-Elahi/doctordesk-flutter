import 'package:flutter/material.dart';
import '../models/user_role.dart';
import 'home_screen.dart';
import 'feed_screen.dart';
import 'appointment_screen.dart';
import 'doctor_manager_screen.dart';
import 'operator_desk_screen.dart';
import 'inbox_screen.dart';
import 'profile_screen.dart';
import '../widgets/app_drawer.dart';

class _RoleMiddleTabConfig {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;

  const _RoleMiddleTabConfig({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });
}

class MainShell extends StatefulWidget {
  final UserRole initialRole;

  const MainShell({
    super.key,
    this.initialRole = UserRole.patient,
  });

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  late UserRole _currentRole;

  static final Map<UserRole, _RoleMiddleTabConfig> _roleConfigs = {
    UserRole.patient: const _RoleMiddleTabConfig(
      label: 'Appointments',
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
      screen: AppointmentScreen(),
    ),
    UserRole.doctor: const _RoleMiddleTabConfig(
      label: 'Manage',
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment,
      screen: DoctorManagerScreen(),
    ),
    UserRole.operator: const _RoleMiddleTabConfig(
      label: 'Desk',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      screen: OperatorDeskScreen(),
    ),
  };

  @override
  void initState() {
    super.initState();
    _currentRole = widget.initialRole;
  }

  void setRole(UserRole role) {
    setState(() {
      _currentRole = role;
    });
  }

  void switchToTab(int index, {String? searchQuery}) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final middleTab = _roleConfigs[_currentRole] ?? _roleConfigs[UserRole.patient]!;

    final List<Widget> pages = [
      HomeScreen(onTabSwitch: switchToTab),
      const FeedScreen(),
      middleTab.screen,
      const InboxScreen(),
      ProfileScreen(role: _currentRole),
    ];

    return Scaffold(
      drawer: const AppDrawer(),
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.dynamic_feed_outlined),
            selectedIcon: Icon(Icons.dynamic_feed),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Icon(middleTab.icon),
            selectedIcon: Icon(middleTab.selectedIcon),
            label: middleTab.label,
          ),
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Inbox',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
