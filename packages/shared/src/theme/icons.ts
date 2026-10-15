import type { ComponentProps } from 'react';
import type MaterialIcons from '@expo/vector-icons/MaterialIcons';

/// A Material icon by its font name (`event-note`, `receipt-long`). The type
/// is the font's own glyph list, so a misspelt name fails to compile.
export type IconName = ComponentProps<typeof MaterialIcons>['name'];
