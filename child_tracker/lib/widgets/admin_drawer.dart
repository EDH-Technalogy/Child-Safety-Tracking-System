import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/child_provider.dart';
import '../providers/locale_provider.dart';
import '../screens/admin/admin_devices_screen.dart';
import '../screens/admin/admin_children_screen.dart';
import '../screens/admin/admin_alerts_screen.dart';
import '../screens/admin/admin_logs_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_users_screen.dart';
import '../screens/admin/admin_home_screen.dart';
import '../screens/admin/admin_map_screen.dart';
import '../screens/admin/admin_add_child_screen.dart';
import '../screens/admin/admin_settings_screen.dart';
import '../screens/admin/admin_account_screen.dart';
import '../screens/login_screen.dart';
import '../utils/photo_provider.dart';

class AdminDrawer extends StatelessWidget {
  const AdminDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localeProvider = context.watch<LocaleProvider>();

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
            child: Consumer<AuthProvider>(
              builder: (context, authProvider, child) {
                final user = authProvider.user;
                final photoProvider = buildPhotoProvider(user?.photo);
                final displayName = (user?.name ?? l10n.admin).trim();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white,
                      backgroundImage: photoProvider,
                      child: photoProvider == null
                          ? Text(
                              displayName.isNotEmpty
                                  ? displayName[0].toUpperCase()
                                  : 'A',
                              style: const TextStyle(
                                color: Color(0xFF2196F3),
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      l10n.adminDrawerAdmin,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Admin Panel Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              l10n.adminPanelSection,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
          ),
          _DrawerItem(
            icon: Icons.dashboard,
            title: l10n.home,
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminDashboardScreen(),
                ),
              );
            },
          ),
          _DrawerItem(
            icon: Icons.people,
            title: l10n.userManagement,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminUsersScreen(),
                ),
              );
            },
          ),
          _DrawerItem(
            icon: Icons.person,
            title: l10n.account,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminAccountScreen(),
                ),
              );
            },
          ),
          _DrawerItem(
            icon: Icons.phone_android,
            title: l10n.deviceManagement,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminDevicesScreen(),
                ),
              );
            },
          ),
          _DrawerItem(
            icon: Icons.child_care,
            title: l10n.children,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminChildrenScreen(),
                ),
              );
            },
          ),
          _DrawerItem(
            icon: Icons.notifications,
            title: l10n.alerts,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminAlertsScreen(),
                ),
              );
            },
          ),
          _DrawerItem(
            icon: Icons.history,
            title: l10n.systemLogs,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminLogsScreen(),
                ),
              );
            },
          ),

          const Divider(),

          // User Pages Section - With Admin Sidebar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              l10n.userPagesSection,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
          ),
          _DrawerItem(
            icon: Icons.home,
            title: l10n.home,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminHomeScreen(),
                ),
              );
            },
          ),
          _DrawerItem(
            icon: Icons.map,
            title: l10n.map,
            onTap: () {
              final childProvider =
                  Provider.of<ChildProvider>(context, listen: false);
              final childId =
                  (childProvider.selectedChild?.id.trim() ?? '').isNotEmpty
                      ? childProvider.selectedChild!.id.trim()
                      : childProvider.children.isNotEmpty
                          ? childProvider.children.first.id.trim()
                          : null;
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminMapScreen(childId: childId),
                ),
              );
            },
          ),
          _DrawerItem(
            icon: Icons.person_add,
            title: l10n.addChild,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminAddChildScreen(),
                ),
              );
            },
          ),
          _DrawerItem(
            icon: Icons.settings,
            title: l10n.settings,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminSettingsScreen(),
                ),
              );
            },
          ),

          const Divider(),

          // Language Settings
          _DrawerItem(
            icon: Icons.language,
            title: l10n.language,
            subtitle: localeProvider.locale.languageCode == 'ps'
                ? l10n.pashto
                : localeProvider.locale.languageCode == 'fa'
                    ? l10n.dari
                    : l10n.english,
            onTap: () {
              _showLanguageDialog(context);
            },
          ),

          const Divider(),
          _DrawerItem(
            icon: Icons.info_outline,
            title: l10n.about,
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/about');
            },
          ),
          const Divider(),
          _DrawerItem(
            icon: Icons.logout,
            title: l10n.logout,
            isLogout: true,
            onTap: () async {
              final authProvider =
                  Provider.of<AuthProvider>(context, listen: false);
              await authProvider.logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(),
                  ),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.selectLanguage),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Radio<String>(
                value: 'en',
                groupValue: localeProvider.locale.languageCode,
                onChanged: (value) {
                  localeProvider.setLocale(const Locale('en'));
                  Navigator.pop(context);
                },
              ),
              title: Text(l10n.english),
              onTap: () {
                localeProvider.setLocale(const Locale('en'));
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Radio<String>(
                value: 'ps',
                groupValue: localeProvider.locale.languageCode,
                onChanged: (value) {
                  localeProvider.setLocale(const Locale('ps'));
                  Navigator.pop(context);
                },
              ),
              title: Text(l10n.pashto),
              onTap: () {
                localeProvider.setLocale(const Locale('ps'));
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Radio<String>(
                value: 'fa',
                groupValue: localeProvider.locale.languageCode,
                onChanged: (value) {
                  localeProvider.setLocale(const Locale('fa'));
                  Navigator.pop(context);
                },
              ),
              title: Text(l10n.dari),
              onTap: () {
                localeProvider.setLocale(const Locale('fa'));
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isSelected = false;
  final bool isLogout;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.isLogout = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = isLogout
        ? Colors.red
        : isSelected
            ? Theme.of(context).primaryColor
            : Colors.grey[700]!;

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      selected: isSelected,
      selectedTileColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
      onTap: onTap,
    );
  }
}
