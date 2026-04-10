import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/constants.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpSupportPage extends StatefulWidget {
  const HelpSupportPage({super.key});

  @override
  State<HelpSupportPage> createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage> {
  final _searchController = TextEditingController();
  final _reportController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isSubmitting = false;

  List<Map<String, String>> _faqs(AppLocalizations l10n) => [
        {
          'question': l10n.faqTrackChildQuestion,
          'answer': l10n.faqTrackChildAnswer,
        },
        {
          'question': l10n.faqLowBatteryQuestion,
          'answer': l10n.faqLowBatteryAnswer,
        },
        {
          'question': l10n.faqGeofenceQuestion,
          'answer': l10n.faqGeofenceAnswer,
        },
        {
          'question': l10n.faqLocationUpdateQuestion,
          'answer': l10n.faqLocationUpdateAnswer,
        },
        {
          'question': l10n.faqShareLocationQuestion,
          'answer': l10n.faqShareLocationAnswer,
        },
      ];

  List<Map<String, String>> _filteredFaqs(AppLocalizations l10n) {
    final query = _searchController.text.toLowerCase();
    final faqs = _faqs(l10n);
    if (query.isEmpty) return faqs;
    return faqs
        .where((faq) =>
            faq['question']!.toLowerCase().contains(query) ||
            faq['answer']!.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _submitReport() async {
    final l10n = AppLocalizations.of(context)!;
    if (_reportController.text.isEmpty || _emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(l10n.pleaseFillAllFields),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    // Simulate API call
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    setState(() => _isSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(l10n.reportSubmittedSuccessfully),
          backgroundColor: Colors.green),
    );
    _reportController.clear();
    _emailController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.helpSupport),
        backgroundColor: AppColors.primaryColor,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick Actions
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      l10n.quickActions,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                launchUrl(Uri.parse('tel://emergency')),
                            icon: const Icon(Icons.phone),
                            label: Text(l10n.callSupport),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => launchUrl(
                                Uri.parse('mailto:support@childtracker.com')),
                            icon: const Icon(Icons.email),
                            label: Text(l10n.email),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // FAQ Search
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l10n.searchFaq,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),

            // FAQ Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l10n.frequentlyAskedQuestions,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: _filteredFaqs(l10n).length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final faq = _filteredFaqs(l10n)[index];
                return Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.help),
                    title: Text(faq['question']!),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(faq['answer']!),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Report Issue Form
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.reportIssue,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: l10n.email,
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reportController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: l10n.describeYourIssue,
                        prefixIcon: Icon(Icons.description),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitReport,
                        child: _isSubmitting
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(l10n.submitting),
                                ],
                              )
                            : Text(l10n.submitReport),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _reportController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}
