import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import '../providers/settings_provider.dart';
import '../services/location_service.dart';
import '../utils/constants.dart';

class LocationSettingsPage extends StatefulWidget {
  const LocationSettingsPage({super.key});

  @override
  State<LocationSettingsPage> createState() => _LocationSettingsPageState();
}

class _LocationSettingsPageState extends State<LocationSettingsPage> {
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
        title: Text(l10n.locationSettings),
        backgroundColor: AppColors.primaryColor,
      ),
      body: Consumer2<SettingsProvider, LocationProvider>(
        builder: (context, settings, location, child) {
          final liveLocation = location.liveLocation;

          if (settings.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: SwitchListTile.adaptive(
                  value: settings.locationTrackingEnabled,
                  onChanged: _toggleLocationTracking,
                  title: Text(l10n.locationSharing),
                  subtitle: Text(l10n.shareLiveLocationWithEmergencyContacts),
                  secondary: const Icon(Icons.location_on),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l10n.status),
                  subtitle: Text(
                    settings.locationTrackingEnabled
                        ? l10n.active
                        : l10n.inactive,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.my_location),
                  title: Text(l10n.location),
                  subtitle: Text(
                    liveLocation == null
                        ? (settings.locationTrackingEnabled
                            ? l10n.loading
                            : l10n.noData)
                        : '${liveLocation.latitude.toStringAsFixed(4)}, '
                            '${liveLocation.longitude.toStringAsFixed(4)}',
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
