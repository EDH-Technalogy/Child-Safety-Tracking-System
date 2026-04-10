import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/settings_provider.dart';
import '../services/location_service.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';

class PrivacySecurityPage extends StatefulWidget {
  const PrivacySecurityPage({super.key});

  @override
  State<PrivacySecurityPage> createState() => _PrivacySecurityPageState();
}

class _PrivacySecurityPageState extends State<PrivacySecurityPage> {
  bool _autoUpdate = true;
  final LocationService _locationService = LocationService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().loadSettings();
    });
  }

  Future<void> _toggleLocationTracking(bool value) async {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final location = context.read<LocationProvider>();
    final authProvider = context.read<AuthProvider>();

    if (value) {
      final hasPermission = await _locationService.requestLocationPermission();
      if (!hasPermission) {
        await settings.setLocationTrackingEnabled(false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.locationPermissionRequired),
            backgroundColor: AppColors.errorColor,
          ),
        );
        return;
      }

      await settings.setLocationTrackingEnabled(true);
      await location.startLocalTracking(authProvider.user?.id ?? 'device');
    } else {
      await settings.setLocationTrackingEnabled(false);
      await location.stopLocalTracking();
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value ? l10n.locationTrackingEnabled : l10n.locationTrackingDisabled,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.privacySecurity),
        backgroundColor: AppColors.primaryColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.privacyPolicy,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.privacyPolicyBody,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Consumer<SettingsProvider>(
              builder: (context, settings, child) => Card(
                child: SwitchListTile.adaptive(
                  value: settings.notificationEnabled,
                  onChanged: (value) async {
                    final notificationProvider =
                        context.read<NotificationProvider>();
                    await settings.setNotificationEnabled(value);
                    await notificationProvider.setEnabled(value);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(value
                              ? l10n.notificationsEnabled
                              : l10n.notificationsDisabled)),
                    );
                  },
                  title: Text(l10n.notifications),
                  subtitle:
                      Text(l10n.receiveAlertsForLowBatteryAndGeofenceExits),
                  secondary: const Icon(Icons.notifications),
                ),
              ),
            ),
            Consumer2<SettingsProvider, LocationProvider>(
              builder: (context, settings, location, child) => Card(
                child: SwitchListTile.adaptive(
                  value: settings.locationTrackingEnabled,
                  onChanged: _toggleLocationTracking,
                  title: Text(l10n.locationSharing),
                  subtitle: Text(l10n.shareLiveLocationWithEmergencyContacts),
                  secondary: const Icon(Icons.location_on),
                ),
              ),
            ),
            Card(
              child: SwitchListTile.adaptive(
                value: _autoUpdate,
                onChanged: (value) {
                  setState(() {
                    _autoUpdate = value;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(value
                            ? l10n.autoUpdatesEnabled
                            : l10n.autoUpdatesDisabled)),
                  );
                },
                title: Text(l10n.autoUpdates),
                subtitle: Text(l10n.autoUpdatesSubtitle),
                secondary: const Icon(Icons.system_update),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock),
                title: Text(l10n.changePassword),
                subtitle: Text(l10n.updateYourAccountPassword),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: _openForgotPasswordFlow,
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.delete),
                title: Text(l10n.deleteAccount),
                subtitle: Text(l10n.deleteAccountSubtitle),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () => _showDeleteAccountDialog(l10n),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.dataUsage,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.locationHistoryRetention),
                    Text(l10n.activityLogsRetention),
                    Text(l10n.deviceDataRealTime),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _showDataExportDialog(l10n),
                      icon: const Icon(Icons.download),
                      label: Text(l10n.exportMyData),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openForgotPasswordFlow() {
    Navigator.pushNamed(context, '/forgot-password');
  }

  void _showDeleteAccountDialog(AppLocalizations l10n) {
    final authProvider = context.read<AuthProvider>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteAccount),
        content: Text(l10n.deleteAccountConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final success = await authProvider.deleteCurrentAccount();
              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? l10n.accountDeleted
                        : authProvider.error != null
                            ? localizeRawMessage(l10n, authProvider.error!)
                            : l10n.error,
                  ),
                  backgroundColor:
                      success ? AppColors.successColor : AppColors.errorColor,
                ),
              );

              if (success) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (route) => false,
                );
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _showDataExportDialog(AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.exportData),
        content: Text(l10n.exportDataDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.exportStartedCheckEmail)),
              );
            },
            child: Text(l10n.exportData),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
