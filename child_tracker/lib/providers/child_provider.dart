import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/child_model.dart';

class ChildProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<ChildModel> _children = [];
  ChildModel? _selectedChild;
  String? _loadedUserId;
  bool _isLoading = false;
  String? _error;

  List<ChildModel> get children => _children;
  ChildModel? get selectedChild => _selectedChild;
  bool get isLoading => _isLoading;
  String? get error => _error;

  ChildModel _mergeChildSnapshot(ChildModel existing, ChildModel incoming) {
    return incoming.copyWith(
      device: incoming.device ?? existing.device,
      createdAt: incoming.createdAt != 0 ? incoming.createdAt : existing.createdAt,
      status: incoming.status.isNotEmpty ? incoming.status : existing.status,
      userId: incoming.userId.isNotEmpty ? incoming.userId : existing.userId,
      name: incoming.name.isNotEmpty ? incoming.name : existing.name,
    );
  }

  ChildModel _mergeWithKnownState(ChildModel incoming) {
    var merged = incoming;

    final existingIndex = _children.indexWhere((child) => child.id == incoming.id);
    if (existingIndex != -1) {
      merged = _mergeChildSnapshot(_children[existingIndex], merged);
    }

    if (_selectedChild?.id == incoming.id) {
      merged = _mergeChildSnapshot(_selectedChild!, merged);
    }

    return merged;
  }

  void _syncChildInState(
    ChildModel incoming, {
    bool updateSelected = false,
  }) {
    final merged = _mergeWithKnownState(incoming);
    final existingIndex = _children.indexWhere((child) => child.id == merged.id);
    final belongsToLoadedScope = (_loadedUserId ?? '').isNotEmpty &&
        merged.userId == _loadedUserId;

    if (existingIndex != -1) {
      _children[existingIndex] = merged;
    } else if (belongsToLoadedScope) {
      _children = [..._children, merged];
    }

    if (_selectedChild?.id == merged.id) {
      _selectedChild = merged;
    } else if (updateSelected) {
      _selectedChild = merged;
    }
  }

  void syncChildFromJson(
    Map<String, dynamic> childJson, {
    Map<String, dynamic>? deviceJson,
    bool updateSelected = false,
  }) {
    if (childJson.isEmpty) {
      return;
    }

    final child = ChildModel.fromJson({
      ...childJson,
      if (deviceJson != null) 'device': deviceJson,
    });

    _syncChildInState(child, updateSelected: updateSelected);
    notifyListeners();
  }

  Future<bool> loadChildren(String userId) async {
    _isLoading = true;
    _error = null;
    _loadedUserId = userId;
    notifyListeners();

    try {
      final response = await _apiService.getChildren(userId);
      final nextChildren = response
          .map((json) => ChildModel.fromJson(Map<String, dynamic>.from(json as Map)))
          .map(_mergeWithKnownState)
          .toList();

      _children = nextChildren;
      if (_selectedChild != null) {
        final selectedIndex =
            _children.indexWhere((child) => child.id == _selectedChild!.id);
        if (selectedIndex != -1) {
          _selectedChild =
              _mergeChildSnapshot(_selectedChild!, _children[selectedIndex]);
          _children[selectedIndex] = _selectedChild!;
        }
      }
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> addChild({
    required String userId,
    required String name,
    required int age,
    String? photo,
    String? imei,
    String? simNumber,
    String? firmware,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.addChild(
        userId: userId,
        name: name,
        age: age,
        photo: photo,
        imei: imei,
        simNumber: simNumber,
        firmware: firmware,
      );

      final resolvedUserId =
          (response['user_id'] ?? '').toString().trim().isNotEmpty
              ? response['user_id'].toString()
              : userId;

      // Reload children list
      await loadChildren(resolvedUserId);
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateChild({
    required String childId,
    required String name,
    required int age,
    String? photo,
    required String userId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _apiService.updateChild(
        childId: childId,
        name: name,
        age: age,
        photo: photo,
      );

      // Reload children list
      await loadChildren(userId);
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeChild(String childId, String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _apiService.removeChild(childId);

      // Reload children list
      await loadChildren(userId);
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> getChildById(String childId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getChildById(childId);
      syncChildFromJson(response, updateSelected: true);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> getChildWithDevice(String childId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getChildWithDevice(childId);
      syncChildFromJson(
        Map<String, dynamic>.from(response['child'] as Map),
        deviceJson: response['device'] is Map
            ? Map<String, dynamic>.from(response['device'] as Map)
            : null,
        updateSelected: true,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void selectChild(ChildModel child) {
    _selectedChild = child;
    notifyListeners();
  }

  void clearSelectedChild() {
    _selectedChild = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
