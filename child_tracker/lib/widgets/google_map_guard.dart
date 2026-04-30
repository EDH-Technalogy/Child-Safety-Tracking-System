import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/google_maps_js_availability.dart';

class GoogleMapAvailabilityGuard extends StatefulWidget {
  final WidgetBuilder mapBuilder;
  final WidgetBuilder fallbackBuilder;
  final Duration retryInterval;
  final int maxRetries;

  const GoogleMapAvailabilityGuard({
    super.key,
    required this.mapBuilder,
    required this.fallbackBuilder,
    this.retryInterval = const Duration(milliseconds: 500),
    this.maxRetries = 20,
  });

  @override
  State<GoogleMapAvailabilityGuard> createState() =>
      _GoogleMapAvailabilityGuardState();
}

class _GoogleMapAvailabilityGuardState
    extends State<GoogleMapAvailabilityGuard> {
  Timer? _retryTimer;
  int _retryCount = 0;
  late bool _isAvailable;

  @override
  void initState() {
    super.initState();
    _isAvailable = !kIsWeb || isGoogleMapsJsAvailable;
    _startRetryLoopIfNeeded();
  }

  @override
  void didUpdateWidget(covariant GoogleMapAvailabilityGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _startRetryLoopIfNeeded();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _startRetryLoopIfNeeded() {
    if (!kIsWeb || _isAvailable || _retryTimer != null) {
      return;
    }

    _retryCount = 0;
    _retryTimer = Timer.periodic(widget.retryInterval, (timer) {
      final availableNow = isGoogleMapsJsAvailable;
      if (availableNow) {
        timer.cancel();
        _retryTimer = null;
        if (mounted) {
          setState(() {
            _isAvailable = true;
          });
        }
        return;
      }

      _retryCount += 1;
      if (_retryCount >= widget.maxRetries) {
        timer.cancel();
        _retryTimer = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isAvailable) {
      return widget.mapBuilder(context);
    }

    return widget.fallbackBuilder(context);
  }
}

class GoogleMapUnavailableState extends StatelessWidget {
  final String title;
  final String message;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;

  const GoogleMapUnavailableState({
    super.key,
    required this.title,
    required this.message,
    this.padding = const EdgeInsets.all(24),
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? Colors.grey[100],
      alignment: Alignment.center,
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.map_outlined,
            size: 44,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
