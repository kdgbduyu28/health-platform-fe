import { View } from 'react-native';
import { Text, Tooltip } from 'react-native-paper';

import {
  type AttentionReason,
  type Patient,
  type PatientFlag,
  attentionReasonLabel,
  isAgeGroup,
  patientFlagMeta,
  patientFlags,
} from '../models/patient';
import { lerpColor, useAppTheme, withAlpha } from '../theme/clinic_theme';
import { Icon } from '../ui/icon';

const remarkBase: Record<PatientFlag, string> = {
  recall: '#3F51B5',
  balance: '#EF6C00',
  no_contact: '#607D8B',
  attention: '#D32F2F',
  pedia: '#009688',
  adult: '#616161',
};

/// A remark's colour, readable on the card behind it in either theme.
export function remarkColor(flag: PatientFlag, dark: boolean): string {
  const base = remarkBase[flag];
  return dark ? lerpColor(base, '#FFFFFF', 0.45) : base;
}

/// One remark on a patient, as a small tinted label. [attention] explains a
/// "Needs attention" in its tooltip.
export function RemarkChip({
  flag,
  attention = new Set(),
  dense = false,
}: {
  flag: PatientFlag;
  attention?: ReadonlySet<AttentionReason>;
  dense?: boolean;
}) {
  const { dark } = useAppTheme();
  const color = remarkColor(flag, dark);
  const meta = patientFlagMeta[flag];
  const chip = (
    <View
      style={{
        flexDirection: 'row',
        alignItems: 'center',
        gap: 4,
        paddingHorizontal: dense ? 6 : 8,
        paddingVertical: 2,
        borderRadius: 6,
        backgroundColor: withAlpha(color, 28 / 255),
        borderWidth: 1,
        borderColor: withAlpha(color, 70 / 255),
      }}
    >
      <Icon name={meta.icon} size={dense ? 12 : 14} color={color} />
      <Text style={{ fontSize: dense ? 11 : 12, fontWeight: '600', color }}>{meta.label}</Text>
    </View>
  );
  if (flag !== 'attention' || attention.size === 0) return chip;
  return (
    <Tooltip title={[...attention].map((r) => attentionReasonLabel[r]).join('\n')}>
      <View>{chip}</View>
    </Tooltip>
  );
}

/// Every remark on a patient, action ones first, the age group last.
export function RemarkChips({
  flags,
  attention = new Set(),
  dense = false,
  showAgeGroup = true,
}: {
  flags: ReadonlySet<PatientFlag>;
  attention?: ReadonlySet<AttentionReason>;
  dense?: boolean;
  showAgeGroup?: boolean;
}) {
  const shown = patientFlags.filter((f) => flags.has(f) && (showAgeGroup || !isAgeGroup(f)));
  if (shown.length === 0) return null;
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 4 }}>
      {shown.map((f) => (
        <RemarkChip key={f} flag={f} attention={attention} dense={dense} />
      ))}
    </View>
  );
}
