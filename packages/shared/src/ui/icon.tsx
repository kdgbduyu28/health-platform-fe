import MaterialCommunityIcons from '@expo/vector-icons/MaterialCommunityIcons';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import type { StyleProp, TextStyle } from 'react-native';

import type { IconName } from '../theme/icons';

export type { IconName };

/// A Material icon. The apps name their icons in Material Icons' own names
/// (`event-note`, `receipt-long`), the set Flutter's `Icons` came from.
export function Icon({
  name,
  size = 24,
  color,
  style,
}: {
  name: IconName;
  size?: number;
  color?: string;
  style?: StyleProp<TextStyle>;
}) {
  return <MaterialIcons name={name} size={size} color={color} style={style} />;
}

const materialGlyphs = MaterialIcons.glyphMap as Record<string, number>;

/// How Paper draws an icon given by name. Ours are Material Icons names;
/// Paper's own (its checkmarks, chevrons and the back arrow) are Material
/// Community Icons names, so a name the first set lacks is looked up in the
/// second.
export function PaperIcon({
  name,
  size,
  color,
  direction,
}: {
  name: string;
  size: number;
  color?: string;
  direction?: 'rtl' | 'ltr';
}) {
  const style = direction === 'rtl' ? { transform: [{ scaleX: -1 }] } : undefined;
  if (name in materialGlyphs) {
    return <MaterialIcons name={name as IconName} size={size} color={color} style={style} />;
  }
  return (
    <MaterialCommunityIcons
      name={name as keyof typeof MaterialCommunityIcons.glyphMap}
      size={size}
      color={color}
      style={style}
    />
  );
}
