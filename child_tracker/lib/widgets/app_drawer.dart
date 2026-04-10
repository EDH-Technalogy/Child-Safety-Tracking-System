import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/child_provider.dart';
import '../utils/photo_provider.dart';
import '../screens/alerts_screen.dart';
import '../screens/location_history_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

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
          ListTile(
            leading: const Icon(Icons.home),
            title: Text(l10n.home),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacementNamed(context, '/home');
            },
          ),
          ListTile(
            leading: const Icon(Icons.map),
            title: Text(l10n.map),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacementNamed(context, '/map');
            },
          ),
          ListTile(
            leading: const Icon(Icons.child_care),
            title: Text(l10n.addChild),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/add-child');
            },
          ),

          // Monitoring Section
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
            Icons.notifications,
            l10n.alerts,
            () {
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
              final firstChildId = childProvider.children.first.id;
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
            Icons.history,
            l10n.locationHistory,
            () {
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
              final child = childProvider.children.first;
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
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l10n.language),
            subtitle: Text(localeProvider.locale.languageCode == 'ps'
                ? l10n.pashto
                : localeProvider.locale.languageCode == 'fa'
                    ? l10n.dari
                    : l10n.english),
            onTap: () {
              _showLanguageDialog(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(l10n.settings),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/settings');
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.about),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/about');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: Text(l10n.logout, style: const TextStyle(color: Colors.red)),
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

  Widget _buildDrawerItem(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    final Color itemColor = Colors.grey[700]!;
    return ListTile(
      leading: Icon(icon, color: itemColor),
      title: Text(
        title,
        style: TextStyle(color: itemColor),
      ),
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

