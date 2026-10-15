import { View } from 'react-native';
import { Text } from 'react-native-paper';

import { ContentWidth } from '../app/adaptive';
import { useAppTheme } from '../theme/clinic_theme';
import { Page } from '../ui/page';
import { LegalContact, type LegalDocument, legalDated } from './legal_content';

/// A LegalDocument on a page of its own: at `/privacy` and `/terms`, and
/// opened from the create-account form and Settings.
export function LegalDocumentScreen({ document }: { document: LegalDocument }) {
  const { colors } = useAppTheme();
  return (
    <Page title={document.title} maxWidth={ContentWidth.form} back="/">
      <Text selectable style={{ color: colors.onSurfaceVariant, fontSize: 12 }}>
        Effective {legalDated(document)}
      </Text>
      <Text selectable variant="bodyLarge" style={{ marginTop: 8, lineHeight: 24 }}>
        {document.intro}
      </Text>
      {document.sections.map((section, i) => (
        <View key={i} style={{ marginTop: 24 }}>
          <Text selectable variant="titleMedium" style={{ fontWeight: '700' }}>
            {i + 1}. {section.heading}
          </Text>
          {section.body.map((p, j) =>
            p.startsWith('- ') ? (
              <View key={j} style={{ flexDirection: 'row', marginTop: 8, paddingLeft: 4 }}>
                <Text style={{ lineHeight: 20 }}>•  </Text>
                <Text selectable style={{ flex: 1, lineHeight: 20 }}>
                  {p.substring(2)}
                </Text>
              </View>
            ) : (
              <Text key={j} selectable style={{ marginTop: 8, lineHeight: 20 }}>
                {p}
              </Text>
            ),
          )}
        </View>
      ))}
      <Text selectable style={{ marginTop: 32, marginBottom: 24, color: colors.onSurfaceVariant }}>
        Questions? Email {LegalContact.email}.
      </Text>
    </Page>
  );
}
