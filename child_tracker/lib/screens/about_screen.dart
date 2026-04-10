import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/constants.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.about),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.aboutThisAppTitle,
                    style: textTheme.titleLarge?.copyWith(
                      color: AppColors.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.aboutAppName,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${l10n.appVersion}: ${AppConstants.appVersion}',
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.aboutPurposeBody),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _AboutSection(
            title: l10n.aboutFeaturesTitle,
            children: _buildBulletItems(
              l10n.aboutFeaturesList,
              textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          _AboutSection(
            title: l10n.aboutBenefitsTitle,
            children: _buildBulletItems(
              l10n.aboutBenefitsList,
              textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          _AboutSection(
            title: l10n.aboutWhoCanUseTitle,
            children: _buildBulletItems(
              l10n.aboutWhoCanUseList,
              textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          _AboutSection(
            title: l10n.aboutPrivacyTitle,
            children: [
              Text(l10n.aboutPrivacyBody),
            ],
          ),
          const SizedBox(height: 16),
          _AboutSection(
            title: l10n.aboutDeveloperInfoTitle,
            children: const [
              _InfoRow(
                label: 'developer',
                value: AppConstants.aboutDeveloperName,
              ),
              _InfoRow(
                label: 'company',
                value: AppConstants.aboutCompanyName,
              ),
              _InfoRow(
                label: 'email',
                value: AppConstants.aboutSupportEmail,
              ),
              _InfoRow(
                label: 'phone',
                value: AppConstants.aboutSupportPhone,
              ),
              _InfoRow(
                label: 'website',
                value: AppConstants.aboutWebsite,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AboutSection(
            title: l10n.aboutSupportTitle,
            children: [
              Text(l10n.aboutSupportBody),
              const SizedBox(height: 8),
              Text(l10n.aboutSupportContactLine),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${l10n.aboutCopyrightTitle}: ${AppConstants.aboutCopyrightText}',
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _buildBulletItems(String value, TextStyle? style) {
    return value
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '•',
                    style: style?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(item, style: style),
                ),
              ],
            ),
          ),
        )
        .toList();
  }
}

class _AboutSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _AboutSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    String resolvedLabel;

    switch (label) {
      case 'developer':
        resolvedLabel = l10n.aboutDeveloperLabel;
        break;
      case 'company':
        resolvedLabel = l10n.aboutCompanyLabel;
        break;
      case 'email':
        resolvedLabel = l10n.aboutEmailLabel;
        break;
      case 'phone':
        resolvedLabel = l10n.aboutContactNumberLabel;
        break;
      case 'website':
        resolvedLabel = l10n.aboutWebsiteLabel;
        break;
      default:
        resolvedLabel = label;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              resolvedLabel,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
