import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/constants.dart';

import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/location_provider.dart';

class PrivacySecurityPage extends StatefulWidget {
  const PrivacySecurityPage({super.key});

  @override
  State<PrivacySecurityPage> createState() => _PrivacySecurityPageState();
}

class _PrivacySecurityPageState extends State<PrivacySecurityPage> {
  bool _autoUpdate = true;
  final _passwordController = TextEditingController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().loadSettings();
    });
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
                  onChanged: (value) async {
                    await settings.setLocationTrackingEnabled(value);
                    if (value) {
                      await location.startLocalTracking('device');
                    } else {
                      await location.stopLocalTracking();
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(value
                              ? l10n.locationTrackingEnabled
                              : l10n.locationTrackingDisabled)),
                    );
                  },
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
                onTap: () => _showChangePasswordDialog(l10n),
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

  void _showChangePasswordDialog(AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.changePassword),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.newPassword,
                prefixIcon: Icon(Icons.lock),
              ),
              maxLength: 20,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: _passwordController.text.length < 6
                ? null
                : () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.passwordChangedSuccessfully),
                      ),
                    );
                    _passwordController.clear();
                  },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteAccount),
        content: Text(l10n.deleteAccountConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.accountDeleted),
                  backgroundColor: Colors.red,
                ),
              );
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
    _passwordController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}
