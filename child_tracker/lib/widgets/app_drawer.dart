import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/child_provider.dart';
import '../providers/locale_provider.dart';
import '../screens/alerts_screen.dart';
import '../screens/location_history_screen.dart';
import '../utils/photo_provider.dart';
import 'animated_nav_item.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Consumer<AuthProvider>(
                  builder: (context, authProvider, child) {
                    final photoProvider =
                        buildPhotoProvider(authProvider.user?.photo);
                    final displayName =
                        (authProvider.user?.name ?? l10n.profile).trim();

                    return CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white,
                      backgroundImage: photoProvider,
                      child: photoProvider == null
                          ? Text(
                              displayName.isNotEmpty
                                  ? displayName[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                color: Color(0xFF2196F3),
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    );
                  },
                ),
                const SizedBox(height: 12),
                Consumer<AuthProvider>(
                  builder: (context, authProvider, child) {
                    return Text(
                      authProvider.user?.name ?? l10n.profile,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
                Consumer<AuthProvider>(
                  builder: (context, authProvider, child) {
                    return Text(
                      authProvider.user?.email ?? '',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          AnimatedNavItem(
            icon: Icons.home_rounded,
            title: l10n.home,
            isHovered: _hoveredItemKey == 'home',
            isDimmed: _hoveredItemKey != null && _hoveredItemKey != 'home',
            onHoverChanged: (value) => _handleHoverChanged('home', value),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacementNamed(context, '/home');
            },
          ),
          AnimatedNavItem(
            icon: Icons.travel_explore_rounded,
            title: l10n.map,
            isHovered: _hoveredItemKey == 'map',
            isDimmed: _hoveredItemKey != null && _hoveredItemKey != 'map',
            onHoverChanged: (value) => _handleHoverChanged('map', value),
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
              Navigator.pushReplacementNamed(
                context,
                '/map',
                arguments: childId,
              );
            },
          ),
          AnimatedNavItem(
            icon: Icons.person_add_alt_1_rounded,
            title: l10n.addChild,
            isHovered: _hoveredItemKey == 'add_child',
            isDimmed: _hoveredItemKey != null && _hoveredItemKey != 'add_child',
            onHoverChanged: (value) => _handleHoverChanged('add_child', value),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/add-child');
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              l10n.monitoring,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
          ),
          _buildDrawerItem(
            context,
            itemKey: 'alerts',
            icon: Icons.crisis_alert_rounded,
            title: l10n.alerts,
            onTap: () {
              final childProvider =
                  Provider.of<ChildProvider>(context, listen: false);
              Navigator.pop(context);
              if (childProvider.children.isEmpty) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.pleaseAddChildFirst)),
                  );
                }
                return;
              }
              final selectedChild = childProvider.selectedChild;
              final firstChildId = (selectedChild?.id.trim() ?? '').isNotEmpty
                  ? selectedChild!.id.trim()
                  : childProvider.children.first.id;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AlertsScreen(childId: firstChildId),
                ),
              );
            },
          ),
          _buildDrawerItem(
            context,
            itemKey: 'history',
            icon: Icons.timeline_rounded,
            title: l10n.locationHistory,
            onTap: () {
              final childProvider =
                  Provider.of<ChildProvider>(context, listen: false);
              Navigator.pop(context);
              if (childProvider.children.isEmpty) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.pleaseAddChildFirst)),
                  );
                }
                return;
              }
              final child =
                  childProvider.selectedChild ?? childProvider.children.first;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LocationHistoryScreen(
                    childId: child.id,
                    childName: child.name,
                  ),
                ),
              );
            },
          ),
          const Divider(),
          AnimatedNavItem(
            icon: Icons.translate_rounded,
            title: l10n.language,
            subtitle: localeProvider.locale.languageCode == 'ps'
                ? l10n.pashto
                : localeProvider.locale.languageCode == 'fa'
                    ? l10n.dari
                    : l10n.english,
            isHovered: _hoveredItemKey == 'language',
            isDimmed: _hoveredItemKey != null && _hoveredItemKey != 'language',
            onHoverChanged: (value) => _handleHoverChanged('language', value),
            onTap: () {
              _showLanguageDialog(context);
            },
          ),
          AnimatedNavItem(
            icon: Icons.settings_suggest_rounded,
            title: l10n.settings,
            isHovered: _hoveredItemKey == 'settings',
            isDimmed: _hoveredItemKey != null && _hoveredItemKey != 'settings',
            onHoverChanged: (value) => _handleHoverChanged('settings', value),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/settings');
            },
          ),
          AnimatedNavItem(
            icon: Icons.info_rounded,
            title: l10n.about,
            isHovered: _hoveredItemKey == 'about',
            isDimmed: _hoveredItemKey != null && _hoveredItemKey != 'about',
            onHoverChanged: (value) => _handleHoverChanged('about', value),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/about');
            },
          ),
          const Divider(),
          AnimatedNavItem(
            icon: Icons.logout_rounded,
            title: l10n.logout,
            isDanger: true,
            isHovered: _hoveredItemKey == 'logout',
            isDimmed: _hoveredItemKey != null && _hoveredItemKey != 'logout',
            onHoverChanged: (value) => _handleHoverChanged('logout', value),
            onTap: () async {
              final authProvider =
                  Provider.of<AuthProvider>(context, listen: false);
              await authProvider.logout();
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
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

  Widget _buildDrawerItem(
    BuildContext context, {
    required String itemKey,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return AnimatedNavItem(
      icon: icon,
      title: title,
      isHovered: _hoveredItemKey == itemKey,
      isDimmed: _hoveredItemKey != null && _hoveredItemKey != itemKey,
      onHoverChanged: (value) => _handleHoverChanged(itemKey, value),
      onTap: onTap,
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
