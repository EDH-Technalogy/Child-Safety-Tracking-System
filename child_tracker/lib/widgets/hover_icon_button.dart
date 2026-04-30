import 'package:flutter/material.dart';

class HoverIconButton extends StatefulWidget {
  const HoverIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isHovered,
    this.isDimmed = false,
    this.onHoverChanged,
    this.accentColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool? isHovered;
  final bool isDimmed;
  final ValueChanged<bool>? onHoverChanged;
  final Color? accentColor;

  @override
  State<HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<HoverIconButton> {
  static const Duration _duration = Duration(milliseconds: 200);
  static const Curve _curve = Curves.easeOutCubic;

  bool _isLocallyHovered = false;

  bool get _isHovered => widget.isHovered ?? _isLocallyHovered;

  void _handleHover(bool isHovered) {
    if (widget.isHovered == null && mounted) {
      setState(() {
        _isLocallyHovered = isHovered;
      });
    }
    widget.onHoverChanged?.call(isHovered);
  }

  @override
  Widget build(BuildContext context) {
    final accentColor =
        widget.accentColor ?? Theme.of(context).colorScheme.primary;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => _handleHover(true),
        onExit: (_) => _handleHover(false),
        child: AnimatedOpacity(
          duration: _duration,
          curve: _curve,
          opacity: widget.isDimmed ? 0.8 : 1,
          child: AnimatedScale(
            duration: _duration,
            curve: _curve,
            scale: _isHovered
                ? 1.12
                : widget.isDimmed
                    ? 0.95
                    : 1,
            child: AnimatedContainer(
              duration: _duration,
              curve: _curve,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: BoxDecoration(
                color: _isHovered
                    ? accentColor.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: _isHovered
                    ? [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.14),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : const [],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: widget.onPressed,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      widget.icon,
                      color: _isHovered
                          ? accentColor
                          : widget.onPressed == null
                              ? Theme.of(context)
                                  .disabledColor
                                  .withValues(alpha: 0.72)
                              : null,
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
