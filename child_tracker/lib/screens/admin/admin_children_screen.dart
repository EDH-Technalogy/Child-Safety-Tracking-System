import 'package:flutter/material.dart';
import '../../services/admin_api_service.dart';
import '../../models/child_model.dart';
import '../../utils/localization_helpers.dart';
import '../../utils/photo_provider.dart';
import '../../widgets/admin_drawer.dart';
import 'admin_add_child_screen.dart';
import '../safe_zones_screen.dart';

class AdminChildrenScreen extends StatefulWidget {
  const AdminChildrenScreen({super.key});

  @override
  State<AdminChildrenScreen> createState() => _AdminChildrenScreenState();
}

class _AdminChildrenScreenState extends State<AdminChildrenScreen> {
  final AdminApiService _adminApi = AdminApiService();
  List<dynamic> _children = [];
  List<dynamic> _filteredChildren = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterChildren);
    _loadChildren();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatError(Object error) {
    return localizeErrorMessage(context.l10n, error);
  }

  void _showErrorSnackBar(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_formatError(error))),
    );
  }

  void _filterChildren() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredChildren = List<dynamic>.from(_children);
      });
    } else {
      setState(() {
        _filteredChildren = _children.where((child) {
          final name = (child['name'] ?? '').toString().toLowerCase();
          return name.contains(query);
        }).toList();
      });
    }
  }

  Future<void> _loadChildren() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final children = await _adminApi.getAllChildren();
      setState(() {
        _children = children;
        _filteredChildren = List<dynamic>.from(children);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = _formatError(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _blockChild(String childId) async {
    final l10n = context.l10n;
    try {
      await _adminApi.blockChild(childId);
      await _loadChildren();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.childBlockedSuccessfully)),
        );
      }
    } catch (e) {
      _showErrorSnackBar(e);
    }
  }

  Future<void> _unblockChild(String childId) async {
    final l10n = context.l10n;
    try {
      await _adminApi.unblockChild(childId);
      await _loadChildren();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.childUnblockedSuccessfully)),
        );
      }
    } catch (e) {
      _showErrorSnackBar(e);
    }
  }

  Future<void> _deleteChild(String childId) async {
    final l10n = context.l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteChild),
        content: Text(l10n.deleteChildProfileConfirm),
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

    if (confirm != true) return;

    try {
      await _adminApi.deleteChild(childId);
      await _loadChildren();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.childDeletedSuccess)),
        );
      }
    } catch (e) {
      _showErrorSnackBar(e);
    }
  }

  Future<void> _openEditChildScreen(Map<String, dynamic> child) async {
    try {
      final childDetails =
          await _adminApi.getChildWithDevice(child['id'].toString());
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AdminAddChildScreen(
            isEditMode: true,
            initialChild: Map<String, dynamic>.from(
              childDetails['child'] ?? child,
            ),
            initialDevice: childDetails['device'] != null
                ? Map<String, dynamic>.from(childDetails['device'])
                : null,
          ),
        ),
      );

      if (!mounted) return;
      await _loadChildren();
    } catch (e) {
      _showErrorSnackBar(e);
    }
  }

  Future<void> _openSafeZonesScreen(Map<String, dynamic> child) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SafeZonesScreen(childId: child['id'].toString()),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadChildren();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: Text(l10n.childrenManagementTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadChildren,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminAddChildScreen()),
          );
          await _loadChildren();
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.searchByName,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('${l10n.error}: $_error'))
                    : _filteredChildren.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.search_off,
                                    size: 64, color: Colors.grey),
                                const SizedBox(height: 16),
                                Text(l10n.noChildrenFound),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadChildren,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredChildren.length,
                              itemBuilder: (context, index) {
                                final child = Map<String, dynamic>.from(
                                  _filteredChildren[index] as Map,
                                );
                                final status =
                                    (child['status'] ?? 'active').toString();
                                final photoProvider = buildPhotoProvider(
                                  ChildModel.resolvePhotoFromJson(child),
                                );
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: status == 'blocked'
                                          ? Colors.orange.withValues(alpha: 0.1)
                                          : Colors.teal.withValues(alpha: 0.1),
                                      backgroundImage: photoProvider,
                                      child: photoProvider == null
                                          ? Icon(
                                              Icons.child_care,
                                              color: status == 'blocked'
                                                  ? Colors.orange
                                                  : Colors.teal,
                                            )
                                          : null,
                                    ),
                                    title: Text(
                                      child['name'] ?? l10n.unknown,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${l10n.age}: ${child['age'] ?? l10n.unknown}',
                                        ),
                                        if (child['user_id'] != null)
                                          Text(
                                            '${l10n.userId}: ${child['user_id']}',
                                          ),
                                        Text(
                                          '${l10n.status}: ${localizeStatusLabel(l10n, status)}',
                                          style: TextStyle(
                                            color: status == 'blocked'
                                                ? Colors.orange
                                                : Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                    isThreeLine: true,
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) {
                                        switch (value) {
                                          case 'edit':
                                            _openEditChildScreen(child);
                                            break;
                                          case 'block':
                                            _blockChild(child['id'].toString());
                                            break;
                                          case 'unblock':
                                            _unblockChild(
                                                child['id'].toString());
                                            break;
                                          case 'safe_zones':
                                            _openSafeZonesScreen(child);
                                            break;
                                          case 'delete':
                                            _deleteChild(
                                                child['id'].toString());
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'safe_zones',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.location_on),
                                              const SizedBox(width: 8),
                                              Text(l10n.safeZones),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.edit),
                                              const SizedBox(width: 8),
                                              Text(l10n.edit),
                                            ],
                                          ),
                                        ),
                                        if (status != 'blocked')
                                          PopupMenuItem(
                                            value: 'block',
                                            child: Row(
                                              children: [
                                                const Icon(Icons.block,
                                                    color: Colors.orange),
                                                const SizedBox(width: 8),
                                                Text(l10n.block),
                                              ],
                                            ),
                                          ),
                                        if (status == 'blocked')
                                          PopupMenuItem(
                                            value: 'unblock',
                                            child: Row(
                                              children: [
                                                const Icon(Icons.check_circle,
                                                    color: Colors.green),
                                                const SizedBox(width: 8),
                                                Text(l10n.unblock),
                                              ],
                                            ),
                                          ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.delete,
                                                  color: Colors.red),
                                              const SizedBox(width: 8),
                                              Text(l10n.delete),
                                            ],
                                          ),
                                        ),
                                      ],
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
  }
}
