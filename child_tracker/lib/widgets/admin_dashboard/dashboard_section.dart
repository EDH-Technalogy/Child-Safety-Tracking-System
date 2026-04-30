import 'package:flutter/material.dart';

class DashboardSection extends StatelessWidget {
  const DashboardSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackAction = action != null && constraints.maxWidth < 520;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stackAction)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitleBlock(
                    title: title,
                    subtitle: subtitle,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 12),
                  action!,
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _SectionTitleBlock(
                      title: title,
                      subtitle: subtitle,
                      textTheme: textTheme,
                    ),
                  ),
                  if (action != null) ...[
                    const SizedBox(width: 12),
                    action!,
                  ],
                ],
              ),
            const SizedBox(height: 16),
            child,
          ],
        );
      },
    );
  }
}

class _SectionTitleBlock extends StatelessWidget {
  const _SectionTitleBlock({
    required this.title,
    required this.subtitle,
    required this.textTheme,
  });

  final String title;
  final String? subtitle;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF14213D),
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ],
    );
  }
}
