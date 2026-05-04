import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/child_provider.dart';
import '../providers/locale_provider.dart';
import '../screens/admin/admin_account_screen.dart';
import '../screens/admin/admin_add_child_screen.dart';
import '../screens/admin/admin_alerts_screen.dart';
import '../screens/admin/admin_children_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_devices_screen.dart';
import '../screens/admin/admin_home_screen.dart';
import '../screens/admin/admin_logs_screen.dart';
import '../screens/admin/admin_map_screen.dart';
import '../screens/admin/admin_settings_screen.dart';
import '../screens/admin/admin_users_screen.dart';
import '../screens/login_screen.dart';
import '../utils/photo_provider.dart';
import 'animated_nav_item.dart';

class AdminDrawer extends StatefulWidget {
  const AdminDrawer({super.key});

  @override
  State<AdminDrawer> createState() => _AdminDrawerState();
}

class _AdminDrawerState extends State<AdminDrawer> {
  String? _hoveredItemKey;

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
            itemKey: 'admin_dashboard',
            hoveredKey: _hoveredItemKey,
            onHoverChanged: _handleHoverChanged,
            icon: Icons.space_dashboard_rounded,
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
            itemKey: 'admin_users',
            hoveredKey: _hoveredItemKey,
            onHoverChanged: _handleHoverChanged,
            icon: Icons.manage_accounts_rounded,
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
            itemKey: 'admin_account',
            hoveredKey: _hoveredItemKey,
            onHoverChanged: _handleHoverChanged,
            icon: Icons.admin_panel_settings_rounded,
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
            itemKey: 'admin_devices',
            hoveredKey: _hoveredItemKey,
            onHoverChanged: _handleHoverChanged,
            icon: Icons.devices_other_rounded,
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
            itemKey: 'admin_children',
            hoveredKey: _hoveredItemKey,
            onHoverChanged: _handleHoverChanged,
            icon: Icons.face_retouching_natural_rounded,
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
            itemKey: 'admin_alerts',
            hoveredKey: _hoveredItemKey,
            onHoverChanged: _handleHoverChanged,
            icon: Icons.crisis_alert_rounded,
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
            itemKey: 'admin_logs',
            hoveredKey: _hoveredItemKey,
            onHoverChanged: _handleHoverChanged,
            icon: Icons.timeline_rounded,
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
            itemKey: 'user_home',
            hoveredKey: _hoveredItemKey,
            onHoverChanged: _handleHoverChanged,
            icon: Icons.home_work_rounded,
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
            itemKey: 'user_map',
            hoveredKey: _hoveredItemKey,
            onHoverChanged: _handleHoverChanged,
            icon: Icons.travel_explore_rounded,
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
            itemKey: 'user_add_child',
            hoveredKey: _hoveredItemKey,
            onHoverChanged: _handleHoverChanged,
            icon: Icons.person_add_alt_1_rounded,
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
            itemKey: 'user_settings',
            hoveredKey: _hoveredItemKey,
            onHoverChanged: _handleHoverChanged,
            icon: Icons.settings_suggest_rounded,
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
          _DrawerItem(
            itemKey: 'language',
            hoveredKey: _hoveredItemKey,
            onHoverChanged: _handleHoverChanged,
            icon: Icons.translate_rounded,
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
            itemKey: 'about',
            hoveredKey: _hoveredItemKey,
            onHoverChanged: _handleHoverChanged,
            icon: Icons.info_rounded,
            title: l10n.about,
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/about');
            },
          ),
          const Divider(),
          _DrawerItem(
            itemKey: 'logout',
            hoveredKey: _hoveredItemKey,
            onHoverChanged: _handleHoverChanged,
            icon: Icons.logout_rounded,
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

  void _handleHoverChanged(String itemKey, bool isHovered) {
    if (!mounted) {
      return;
    }

    setState(() {
      if (isHovered) {
        _hoveredItemKey = itemKey;
      } else if (_hoveredItemKey == itemKey) {
        _hoveredItemKey = null;
      }
    });
  }

  void _showLanguageDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.selectLanguage),
        content: RadioGroup<String>(
          groupValue: localeProvider.locale.languageCode,
          onChanged: (value) {
            if (value == null) {
              return;
            }
            localeProvider.setLocale(Locale(value));
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Radio<String>(value: 'en'),
                title: Text(l10n.english),
                onTap: () {
                  localeProvider.setLocale(const Locale('en'));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Radio<String>(value: 'ps'),
                title: Text(l10n.pashto),
                onTap: () {
                  localeProvider.setLocale(const Locale('ps'));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Radio<String>(value: 'fa'),
                title: Text(l10n.dari),
                onTap: () {
                  localeProvider.setLocale(const Locale('fa'));
                  Navigator.pop(context);
                },
              ),
            ],
          ),
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
  const _DrawerItem({
    required this.itemKey,
    required this.hoveredKey,
    required this.onHoverChanged,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.isLogout = false,
  });

  final String itemKey;
  final String? hoveredKey;
  final void Function(String itemKey, bool isHovered) onHoverChanged;
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isLogout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedNavItem(
      icon: icon,
      title: title,
      subtitle: subtitle,
      tooltip: title,
      isDanger: isLogout,
      isHovered: hoveredKey == itemKey,
      isDimmed: hoveredKey != null && hoveredKey != itemKey,
      onHoverChanged: (value) => onHoverChanged(itemKey, value),
      onTap: onTap,
    );
  }
}
