import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../services/admin_api_service.dart';
import '../../utils/localization_helpers.dart';
import '../../widgets/admin_drawer.dart';

class AdminDevicesScreen extends StatefulWidget {
  const AdminDevicesScreen({super.key});

  @override
  State<AdminDevicesScreen> createState() => _AdminDevicesScreenState();
}

class _AdminDevicesScreenState extends State<AdminDevicesScreen> {
  AdminApiService? _adminApi;
  List<dynamic> _devices = [];
  List<dynamic> _filteredDevices = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeAuth());
  }

  Future<void> _initializeAuth() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.isAdmin) {
      // Admin authenticated - initialize API
      setState(() {
        _isLoading = false;
        _adminApi =
            AdminApiService(); // Uses SharedPreferences auth internally or global
      });
      _loadDevices();
    } else {
      // Not admin - show error and prompt login
      setState(() {
        _isLoading = false;
        _error = AppLocalizations.of(context)!.adminAccessRequired;
      });
    }
  }

  void _filterDevices() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      _filteredDevices = List.from(_devices);
    } else {
      _filteredDevices = _devices.where((device) {
        return device['id']?.toLowerCase().contains(query) == true ||
            device['imei']?.toLowerCase().contains(query) == true;
      }).toList();
    }
    setState(() {});
  }

  Future<void> _loadDevices() async {
    if (_adminApi == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final devices = await _adminApi!.getAllDevices();
      setState(() {
        _devices = devices;
        _filteredDevices = List.from(devices);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = _formatError(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _activateDevice(String deviceId) async {
    final l10n = context.l10n;
    if (_adminApi == null) return;
    try {
      await _adminApi!.activateDevice(deviceId);
      await _loadDevices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.deviceActivatedSuccessfully)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.error}: ${_formatError(e)}'),
          ),
        );
      }
    }
  }

  Future<void> _deactivateDevice(String deviceId) async {
    final l10n = context.l10n;
    if (_adminApi == null) return;
    try {
      await _adminApi!.deactivateDevice(deviceId);
      await _loadDevices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.deviceDeactivatedSuccessfully)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.error}: ${_formatError(e)}'),
          ),
        );
      }
    }
  }

  Future<void> _deleteDevice(String deviceId) async {
    final l10n = context.l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteDevice),
        content: Text(l10n.deleteDevicePermanentConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirm == true && _adminApi != null) {
      try {
        await _adminApi!.deleteDevice(deviceId);
        await _loadDevices();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.deviceDeletedSuccessfully)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l10n.error}: ${_formatError(e)}'),
            ),
          );
        }
      }
    }
  }

  String _formatError(Object error) {
    return localizeErrorMessage(context.l10n, error);
  }

  Future<void> _handleDeviceAction(
    String value,
    Map<String, dynamic> device,
  ) async {
    switch (value) {
      case 'edit':
        _showEditDeviceDialog(device);
        break;
      case 'activate':
        await _activateDevice(device['id'].toString());
        break;
      case 'deactivate':
        await _deactivateDevice(device['id'].toString());
        break;
      case 'delete':
        await _deleteDevice(device['id'].toString());
        break;
    }
  }

  Future<void> _showDeviceActionsMenu(
    BuildContext buttonContext,
    Map<String, dynamic> device,
  ) async {
    final l10n = context.l10n;
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(buttonContext).context.findRenderObject() as RenderBox;
    final String status =
        (device['status'] ?? 'offline').toString().toLowerCase();

    final selected = await showMenu<String>(
      context: buttonContext,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          button.localToGlobal(Offset.zero, ancestor: overlay),
          button.localToGlobal(button.size.bottomRight(Offset.zero),
              ancestor: overlay),
        ),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit),
              const SizedBox(width: 8),
              Text(l10n.editDevice),
            ],
          ),
        ),
        if (status == 'offline')
          PopupMenuItem(
            value: 'activate',
            child: Row(
              children: [
                const Icon(Icons.play_arrow, color: Colors.green),
                const SizedBox(width: 8),
                Text(l10n.activate),
              ],
            ),
          ),
        if (status == 'online')
          PopupMenuItem(
            value: 'deactivate',
            child: Row(
              children: [
                const Icon(Icons.stop, color: Colors.orange),
                const SizedBox(width: 8),
                Text(l10n.deactivate),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete, color: Colors.red),
              const SizedBox(width: 8),
              Text(l10n.delete),
            ],
          ),
        ),
      ],
    );

    if (selected != null && mounted) {
      await _handleDeviceAction(selected, device);
    }
  }

  void _showDeviceFormDialog({
    required bool isEditMode,
    Map<String, dynamic>? device,
  }) {
    final l10n = context.l10n;
    final childIdController = TextEditingController(
      text: (device?['child_id'] ?? '').toString(),
    );
    final imeiController =
        TextEditingController(text: (device?['imei'] ?? '').toString());
    final simController =
        TextEditingController(text: (device?['sim_number'] ?? '').toString());
    final firmwareController = TextEditingController(
      text:
          isEditMode ? (device?['firmware_version'] ?? '').toString() : '1.0.0',
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEditMode ? l10n.editDevice : l10n.addDevice),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: childIdController,
                decoration: InputDecoration(labelText: l10n.childId),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: imeiController,
                decoration: InputDecoration(labelText: l10n.imei),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: simController,
                decoration: InputDecoration(labelText: l10n.simNumber),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: firmwareController,
                decoration: InputDecoration(labelText: l10n.firmwareVersion),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final childId = childIdController.text.trim();
              final imei = imeiController.text.trim();

              if (childId.isEmpty || imei.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.childIdAndImeiRequired)),
                  );
                }
                return;
              }

              try {
                if (_adminApi != null) {
                  if (isEditMode) {
                    await _adminApi!.updateDevice(
                      deviceId: device!['id'],
                      childId: childId,
                      imei: imei,
                      simNumber: simController.text.trim(),
                      firmware: firmwareController.text.trim(),
                    );
                  } else {
                    await _adminApi!.createDevice(
                      childId: childId,
                      imei: imei,
                      simNumber: simController.text.trim(),
                      firmware: firmwareController.text.trim(),
                    );
                  }
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  await _loadDevices();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isEditMode
                            ? l10n.deviceUpdatedSuccessfully
                            : l10n.deviceAddedSuccessfully,
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${l10n.error}: ${_formatError(e)}'),
                  ),
                );
              }
            },
            child: Text(isEditMode ? l10n.update : l10n.add),
          ),
        ],
      ),
    ).then((_) {
      childIdController.dispose();
      imeiController.dispose();
      simController.dispose();
      firmwareController.dispose();
    });
  }

  void _showEditDeviceDialog(Map<String, dynamic> device) {
    _showDeviceFormDialog(
      isEditMode: true,
      device: device,
    );
  }

  void _showAddDeviceDialog() {
    _showDeviceFormDialog(isEditMode: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Scaffold(
          drawer: const AdminDrawer(),
          appBar: AppBar(
            title: Text(l10n.deviceManagementTitle),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _adminApi != null ? _loadDevices : null,
              ),
            ],
          ),
          floatingActionButton: _adminApi == null
              ? null
              : FloatingActionButton(
                  onPressed: _showAddDeviceDialog,
                  child: const Icon(Icons.add),
                ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: l10n.searchByIdOrImei,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _filterDevices();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (value) => _filterDevices(),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.admin_panel_settings_outlined,
                                  size: 64,
                                  color: Colors.orange,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _error!,
                                  style: const TextStyle(fontSize: 16),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Provider.of<AuthProvider>(context,
                                            listen: false)
                                        .logout();
                                    Navigator.pushReplacementNamed(
                                        context, '/login');
                                  },
                                  icon: const Icon(Icons.logout),
                                  label: Text(l10n.logoutAndLoginAsAdmin),
                                ),
                              ],
                            ),
                          )
                        : _filteredDevices.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.search_off,
                                        size: 64, color: Colors.grey),
                                    const SizedBox(height: 16),
                                    Text(
                                      _searchController.text.isEmpty
                                          ? l10n.noDevicesRegistered
                                          : '${l10n.noDevicesMatch} "${_searchController.text}"',
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _loadDevices,
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _filteredDevices.length,
                                  itemBuilder: (context, index) {
                                    final device = _filteredDevices[index];
                                    final status =
                                        (device['status'] ?? 'offline')
                                            .toString()
                                            .toLowerCase();
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: status == 'online'
                                              ? Colors.green
                                                  .withValues(alpha: 0.1)
                                              : Colors.grey
                                                  .withValues(alpha: 0.1),
                                          child: Icon(
                                            Icons.phone_android,
                                            color: status == 'online'
                                                ? Colors.green
                                                : Colors.grey,
                                          ),
                                        ),
                                        title: Text(
                                          device['imei'] ?? l10n.unknownImei,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                '${l10n.deviceId}: ${device['id'] ?? l10n.unknown}'),
                                            Text(
                                                '${l10n.simNumber}: ${device['sim_number'] ?? l10n.unknown}'),
                                            Text(
                                              '${l10n.firmwareVersion}: ${device['firmware_version'] ?? l10n.unknown}',
                                            ),
                                            Text(
                                              '${l10n.status}: ${localizeStatusLabel(l10n, status)}',
                                              style: TextStyle(
                                                color: status == 'online'
                                                    ? Colors.green
                                                    : Colors.red,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              '${l10n.battery}: ${device['battery_level'] ?? 0}%',
                                            ),
                                          ],
                                        ),
                                        isThreeLine: true,
                                        trailing: Builder(
                                          builder: (buttonContext) =>
                                              IconButton(
                                            icon: const Icon(Icons.more_vert),
                                            onPressed: () =>
                                                _showDeviceActionsMenu(
                                              buttonContext,
                                              device,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
