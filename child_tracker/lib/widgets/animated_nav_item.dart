import 'package:flutter/material.dart';

class AnimatedNavItem extends StatelessWidget {
  const AnimatedNavItem({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.tooltip,
    this.isDanger = false,
    this.isHovered = false,
    this.isDimmed = false,
    this.onHoverChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? tooltip;
  final bool isDanger;
  final bool isHovered;
  final bool isDimmed;
  final ValueChanged<bool>? onHoverChanged;
  final VoidCallback onTap;

  static const Duration _duration = Duration(milliseconds: 200);
  static const Curve _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textDirection = Directionality.of(context);
    final accentColor = isDanger ? Colors.red : theme.colorScheme.primary;
    final titleColor = isDanger
        ? Colors.red
        : isHovered
            ? const Color(0xFF0F172A)
            : const Color(0xFF334155);
    final subtitleColor = isDanger
        ? Colors.red.withValues(alpha: 0.72)
        : const Color(0xFF64748B);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Tooltip(
        message: tooltip ?? title,
        waitDuration: const Duration(milliseconds: 350),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => onHoverChanged?.call(true),
          onExit: (_) => onHoverChanged?.call(false),
          child: AnimatedOpacity(
            duration: _duration,
            curve: _curve,
            opacity: isDimmed ? 0.82 : 1,
            child: AnimatedScale(
              duration: _duration,
              curve: _curve,
              scale: isHovered
                  ? 1.08
                  : isDimmed
                      ? 0.965
                      : 1,
              child: AnimatedContainer(
                duration: _duration,
                curve: _curve,
                decoration: BoxDecoration(
                  color: isHovered
                      ? accentColor.withValues(alpha: isDanger ? 0.08 : 0.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isHovered
                        ? accentColor.withValues(alpha: 0.22)
                        : Colors.transparent,
                  ),
                  boxShadow: isHovered
                      ? [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.12),
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                          ),
                        ]
                      : const [],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        14,
                        12,
                        14,
                        12,
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: _duration,
                            curve: _curve,
                            width: isHovered ? 44 : 40,
                            height: isHovered ? 44 : 40,
                            decoration: BoxDecoration(
                              color: accentColor.withValues(
                                alpha: isHovered ? 0.18 : 0.12,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              icon,
                              size: isHovered ? 23 : 21,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: titleColor,
                                    fontWeight: isHovered
                                        ? FontWeight.w800
                                        : FontWeight.w700,
                                  ),
                                ),
                                if (subtitle != null &&
                                    subtitle!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: subtitleColor,
                                      fontWeight: isHovered
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          AnimatedContainer(
                            duration: _duration,
                            curve: _curve,
                            transform: Matrix4.identity()
                              ..translate(isHovered ? 2.0 : 0.0),
                            child: Icon(
                              textDirection == TextDirection.rtl
                                  ? Icons.chevron_left_rounded
                                  : Icons.chevron_right_rounded,
                              color: isHovered
                                  ? accentColor
                                  : titleColor.withValues(alpha: 0.48),
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
      ),
    );
  }
}
