import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/notification_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/constants.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().loadSettings();
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final notificationProvider = context.read<NotificationProvider>();

    await settings.setNotificationEnabled(value);
    await notificationProvider.setEnabled(value);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value ? l10n.notificationsEnabled : l10n.notificationsDisabled,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notificationSettings),
        backgroundColor: AppColors.primaryColor,
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          if (settings.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: SwitchListTile.adaptive(
                  value: settings.notificationEnabled,
                  onChanged: _toggleNotifications,
                  title: Text(l10n.notifications),
                  subtitle: Text(
                    l10n.receiveAlertsForLowBatteryAndGeofenceExits,
                  ),
                  secondary: const Icon(Icons.notifications_active),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l10n.status),
                  subtitle: Text(
                    settings.notificationEnabled ? l10n.active : l10n.inactive,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
