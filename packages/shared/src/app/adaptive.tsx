import { Children, type ReactNode, createContext, useContext, useState } from 'react';
import { type LayoutChangeEvent, type StyleProp, View, type ViewStyle, useWindowDimensions } from 'react-native';

/// Window widths the layout changes at.
///
///   phone     < 600    tabs in a bar along the bottom
///   tablet    600–1199 tabs in a rail down the side
///   desktop   ≥ 1200   the rail widens to show the tab names
export const Breakpoints = {
  medium: 600,
  expanded: 1200,
  /// Wide enough for a page to set two columns side by side.
  twoPane: 840,
};

/// How wide a page's content may grow before it stops and centres, so a line
/// of text or a row of fields never runs the width of a desktop monitor.
export const ContentWidth = {
  /// A form, or one thing being read: a sign-in, a booking, a bill.
  form: 640,
  /// A single column of cards: a list of visits, a list of bills.
  list: 840,
  /// A detail page, which may split into two columns.
  detail: 1080,
  /// Lists and dashboards, which fill up with columns of cards.
  wide: 1320,
};

export type WindowSize = 'compact' | 'medium' | 'expanded';

export function windowSizeFor(width: number): WindowSize {
  if (width >= Breakpoints.expanded) return 'expanded';
  if (width >= Breakpoints.medium) return 'medium';
  return 'compact';
}

export function useWindowSize(): WindowSize {
  return windowSizeFor(useWindowDimensions().width);
}

export function useIsCompact(): boolean {
  return useWindowSize() === 'compact';
}

/// The width a box was laid out at, once it has been. For layouts that
/// depend on their own width rather than the window's (Flutter's
/// LayoutBuilder): render with the window width first, then the real one.
export function useLayoutWidth(): [number, (e: LayoutChangeEvent) => void] {
  const window = useWindowDimensions().width;
  const [width, setWidth] = useState<number | null>(null);
  return [width ?? window, (e) => setWidth(e.nativeEvent.layout.width)];
}

/// [children] no wider than [maxWidth], centred. For content that does not
/// scroll, or a block inside a scroll view.
export function Centered({
  children,
  maxWidth = ContentWidth.wide,
  style,
}: {
  children: ReactNode;
  maxWidth?: number;
  style?: StyleProp<ViewStyle>;
}) {
  return <View style={[{ width: '100%', maxWidth, alignSelf: 'center' }, style]}>{children}</View>;
}

/// How many columns [width] fits.
export function columnsFor(width: number, minItemWidth = 360, maxColumns = 3, spacing = 12): number {
  return Math.min(maxColumns, Math.max(1, Math.floor((width + spacing) / (minItemWidth + spacing))));
}

/// [children] in as many equal columns as fit at [minItemWidth] each, up to
/// [maxColumns]: one on a phone, two or three on a tablet or desktop.
export function CardColumns({
  children,
  minItemWidth = 360,
  maxColumns = 3,
  spacing = 12,
  runSpacing = 8,
}: {
  children: ReactNode;
  minItemWidth?: number;
  maxColumns?: number;
  spacing?: number;
  runSpacing?: number;
}) {
  const [width, onLayout] = useLayoutWidth();
  const items = Children.toArray(children);
  const columns = columnsFor(width, minItemWidth, maxColumns, spacing);
  if (columns === 1) {
    return (
      <View onLayout={onLayout} style={{ gap: runSpacing }}>
        {items}
      </View>
    );
  }
  // Rows rather than a wrap, so a short last row keeps the column widths.
  const rows: ReactNode[] = [];
  for (let start = 0; start < items.length; start += columns) {
    const cells: ReactNode[] = [];
    for (let i = start; i < start + columns; i++) {
      cells.push(
        <View key={i} style={{ flex: 1, minWidth: 0 }}>
          {i < items.length ? items[i] : null}
        </View>,
      );
    }
    rows.push(
      <View key={start} style={{ flexDirection: 'row', alignItems: 'flex-start', gap: spacing }}>
        {cells}
      </View>,
    );
  }
  return (
    <View onLayout={onLayout} style={{ gap: runSpacing }}>
      {rows}
    </View>
  );
}

/// Two columns side by side once there is room ([Breakpoints.twoPane] of
/// width), one after the other before that: [start] then [end].
///
/// For a detail page whose sections split naturally: who and what on one
/// side, the history or the actions on the other. Pass [narrow] when the
/// single column wants another order than [start] then [end].
///
/// [below] runs the full width under both columns once they split: for
/// something that needs the room, like a dental chart. A single column
/// leaves it out, so put it in [narrow] too.
export function SplitColumns({
  start,
  end,
  below,
  narrow,
  startFlex = 1,
  endFlex = 1,
  spacing = 24,
  breakpoint = Breakpoints.twoPane,
}: {
  start: ReactNode;
  end: ReactNode;
  below?: ReactNode;
  narrow?: ReactNode;
  startFlex?: number;
  endFlex?: number;
  spacing?: number;
  breakpoint?: number;
}) {
  const [width, onLayout] = useLayoutWidth();
  if (width < breakpoint) {
    return (
      <View onLayout={onLayout}>
        {narrow ?? (
          <>
            {start}
            {end}
            {below}
          </>
        )}
      </View>
    );
  }
  return (
    <View onLayout={onLayout}>
      <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: spacing }}>
        <View style={{ flex: startFlex, minWidth: 0 }}>{start}</View>
        <View style={{ flex: endFlex, minWidth: 0 }}>{end}</View>
      </View>
      {below}
    </View>
  );
}

/// Whether the rail beside this page already names the clinic (a desktop), so
/// the page's own title can name the page instead of the clinic again.
export const RailShowsClinicContext = createContext(false);

export function useRailShowsClinic(): boolean {
  return useContext(RailShowsClinicContext);
}
