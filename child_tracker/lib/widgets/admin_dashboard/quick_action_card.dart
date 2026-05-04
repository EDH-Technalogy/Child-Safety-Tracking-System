import 'package:flutter/material.dart';

import 'dashboard_models.dart';

class QuickActionCard extends StatelessWidget {
  const QuickActionCard({
    super.key,
    required this.action,
    this.isHovered = false,
    this.isDimmed = false,
    this.onHoverChanged,
  });

  final DashboardQuickAction action;
  final bool isHovered;
  final bool isDimmed;
  final ValueChanged<bool>? onHoverChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final textDirection = Directionality.of(context);

    return Tooltip(
      message: action.title,
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHoverChanged?.call(true),
        onExit: (_) => onHoverChanged?.call(false),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          opacity: isDimmed ? 0.82 : 1,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            scale: isHovered
                ? 1.10
                : isDimmed
                    ? 0.96
                    : 1,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: action.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: action.accentColor.withValues(
                        alpha: isHovered ? 0.26 : 0.10,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: action.accentColor.withValues(
                          alpha: isHovered ? 0.14 : 0.04,
                        ),
                        blurRadius: isHovered ? 28 : 22,
                        offset: Offset(0, isHovered ? 14 : 10),
                      ),
                    ],
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        action.accentColor.withValues(
                          alpha: isHovered ? 0.09 : 0.04,
                        ),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutCubic,
                              width: isHovered ? 50 : 46,
                              height: isHovered ? 50 : 46,
                              decoration: BoxDecoration(
                                color: action.accentColor.withValues(
                                  alpha: isHovered ? 0.18 : 0.12,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                action.icon,
                                color: action.accentColor,
                                size: isHovered ? 24 : 22,
                              ),
                            ),
                            const Spacer(),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutCubic,
                              transform: Matrix4.identity()
                                ..translateByDouble(
                                  isHovered ? 3.0 : 0.0,
                                  0,
                                  0,
                                  1,
                                ),
                              child: Icon(
                                textDirection == TextDirection.rtl
                                    ? Icons.chevron_left_rounded
                                    : Icons.chevron_right_rounded,
                                color: isHovered
                                    ? action.accentColor
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                action.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: isHovered
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  color: const Color(0xFF14213D),
                                  height: 1.18,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                action.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF64748B),
                                  height: 1.25,
                                  fontWeight: isHovered
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
