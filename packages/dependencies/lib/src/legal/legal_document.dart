import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/adaptive_layout.dart';

/// Who runs the platform, and where privacy and support requests go. The
/// same address serves as the Data Protection Officer's.
abstract final class LegalContact {
  static const operator = String.fromEnvironment(
    'LEGAL_OPERATOR',
    defaultValue: 'D-Touch Dental Clinic',
  );

  static const email = String.fromEnvironment(
    'LEGAL_EMAIL',
    defaultValue: 'dtouchdental@gmail.com',
  );
}

/// A policy the apps show and people agree to: the Privacy Policy, the Terms
/// and Conditions.
///
/// [version] is the document's date. Each account's acknowledgement records
/// it (health-platform-be, policy_acknowledgements), so bump it whenever the
/// wording changes what someone agreed to.
class LegalDocument {
  const LegalDocument({
    required this.id,
    required this.title,
    required this.version,
    required this.intro,
    required this.sections,
  });

  /// As the database names it: `privacy` or `terms`.
  final String id;
  final String title;
  final String version;
  final String intro;
  final List<LegalSection> sections;

  /// `September 30, 2026`.
  String get dated => DateFormat('MMMM d, y').format(DateTime.parse(version));
}

/// A heading and its paragraphs. A paragraph starting with `- ` is drawn as
/// a bullet.
class LegalSection {
  const LegalSection(this.heading, this.body);

  final String heading;
  final List<String> body;
}

/// A [LegalDocument] on a page of its own: at `/privacy` and `/terms`, and
/// pushed from the create-account form and Settings.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: CenteredScroll(
        maxWidth: ContentWidth.form,
        builder: (padding) => SelectionArea(
          child: ListView(
            padding: padding,
            children: [
              Text(
                'Effective ${document.dated}',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(document.intro,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
              for (final (i, section) in document.sections.indexed) ...[
                const SizedBox(height: 24),
                Text(
                  '${i + 1}. ${section.heading}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                for (final p in section.body) ...[
                  const SizedBox(height: 8),
                  if (p.startsWith('- '))
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  ', style: TextStyle(height: 1.4)),
                          Expanded(
                            child: Text(p.substring(2),
                                style: const TextStyle(height: 1.4)),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(p, style: const TextStyle(height: 1.4)),
                ],
              ],
              const SizedBox(height: 32),
              Text(
                'Questions? Email ${LegalContact.email}.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
