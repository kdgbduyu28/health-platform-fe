import { Asset } from 'expo-asset';
import { useState } from 'react';
import { Image, type ImageSourcePropType, View } from 'react-native';
import Svg, { Defs, LinearGradient, Rect, Stop } from 'react-native-svg';

import type { Clinic } from '../models/clinic';
import { Icon } from '../ui/icon';
import { Brand, useAppTheme } from './clinic_theme';

/// Artwork bundled with the apps, by the path a clinic row names after
/// `asset:`. A stopgap for logos that predate uploads; see Brand.
const bundledAssets: Record<string, ImageSourcePropType> = {
  'assets/brand/dtouch_mark.png': require('../../assets/brand/dtouch_mark.png'),
  'assets/brand/dtouch_wordmark.png': require('../../assets/brand/dtouch_wordmark.png'),
};

/// A clinic image from the bundle or the web, or null for a bundled path this
/// build does not have.
export function clinicImageSource(url: string): ImageSourcePropType | null {
  if (url.startsWith(Brand.bundledAssetScheme)) {
    return bundledAssets[url.substring(Brand.bundledAssetScheme.length)] ?? null;
  }
  return { uri: url };
}

/// A clinic image as an address a separate page can load: a hosted URL as
/// it is, a bundled one where the build serves it. For the printed statement.
export function clinicImageUrl(url: string): string | null {
  if (!url.startsWith(Brand.bundledAssetScheme)) return url;
  const mod = bundledAssets[url.substring(Brand.bundledAssetScheme.length)];
  if (mod == null) return null;
  try {
    return Asset.fromModule(mod as number).uri;
  } catch {
    return null;
  }
}

/// A clinic's square mark: its logo if it has one, otherwise its vertical's
/// icon on the theme colour. With no clinic, the platform's generic mark.
export function ClinicMark({ clinic = null, size = 48 }: { clinic?: Clinic | null; size?: number }) {
  const [failed, setFailed] = useState<string | null>(null);
  const url = clinic?.logoUrl;
  const source = url ? clinicImageSource(url) : null;
  // A broken or unreachable logo URL must not leave a hole in the app bar.
  if (url && source && failed !== url) {
    return (
      <Image
        source={source}
        onError={() => setFailed(url)}
        // Named for screen readers, which cannot read pixels.
        accessibilityLabel={clinic!.name}
        resizeMode="contain"
        style={{ width: size, height: size }}
      />
    );
  }
  return <IconTile icon={clinic?.icon ?? 'local-hospital'} size={size} />;
}

function IconTile({ icon, size }: { icon: Clinic['icon']; size: number }) {
  const { colors } = useAppTheme();
  const radius = size * 0.28;
  return (
    <View style={{ width: size, height: size, borderRadius: radius, overflow: 'hidden' }}>
      <Svg width={size} height={size} style={{ position: 'absolute' }}>
        <Defs>
          <LinearGradient id="mark" x1="0" y1="0" x2="1" y2="1">
            <Stop offset="0" stopColor={colors.primary} />
            <Stop offset="1" stopColor={colors.secondary} />
          </LinearGradient>
        </Defs>
        <Rect width={size} height={size} rx={radius} fill="url(#mark)" />
      </Svg>
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <Icon name={icon} size={size * 0.5} color={colors.onPrimary} />
      </View>
    </View>
  );
}
