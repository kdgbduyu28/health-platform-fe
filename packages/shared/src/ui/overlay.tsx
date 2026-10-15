import { type ReactNode, createContext, useCallback, useContext, useMemo, useRef, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View, useWindowDimensions } from 'react-native';
import { Button, Dialog, Portal, Snackbar, Text } from 'react-native-paper';

import { Breakpoints } from '../app/adaptive';
import { useAppTheme } from '../theme/clinic_theme';

/// Closes the overlay it was handed to, answering [value] to whoever opened
/// it.
export type Close<T> = (value?: T) => void;

type Entry = {
  id: number;
  kind: 'dialog' | 'sheet' | 'page';
  dismissible: boolean;
  render: (close: Close<any>) => ReactNode;
  resolve: (value: any) => void;
};

type SnackRequest = { id: number; message: string; action?: { label: string; onPress: () => void }; duration: number };

type OverlayApi = {
  /// Shows [render] as a dialog and answers what it closes with: Flutter's
  /// `showDialog`. Undefined when dismissed by the backdrop or Escape.
  showDialog<T>(render: (close: Close<T>) => ReactNode, opts?: { dismissible?: boolean }): Promise<T | undefined>;
  /// The same as a sheet: up from the bottom on a phone, a centred panel on a
  /// wider screen. Flutter's `showModalBottomSheet`.
  showSheet<T>(render: (close: Close<T>) => ReactNode, opts?: { dismissible?: boolean }): Promise<T | undefined>;
  /// A whole page over the current one, with no address of its own: what
  /// Flutter's `Navigator.push(MaterialPageRoute(…))` was for. A Page inside
  /// it gets a back button that closes it.
  showPage<T>(render: (close: Close<T>) => ReactNode): Promise<T | undefined>;
  /// A short message along the bottom: Flutter's `showSnackBar`.
  snack(message: string, opts?: { action?: { label: string; onPress: () => void }; duration?: number }): void;
  /// Asks a yes-or-no question. True for yes.
  confirm(opts: ConfirmOptions): Promise<boolean>;
};

export type ConfirmOptions = {
  title: string;
  message?: ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  /// A red confirm button, for what cannot be undone.
  destructive?: boolean;
};

const OverlayContext = createContext<OverlayApi | null>(null);

export function useOverlay(): OverlayApi {
  const api = useContext(OverlayContext);
  if (api == null) throw new Error('useOverlay needs an OverlayHost above it.');
  return api;
}

/// Hosts every dialog, sheet and snackbar the app opens. Goes inside the
/// theme and data providers, so what it shows can use them.
export function OverlayHost({ children }: { children: ReactNode }) {
  const [entries, setEntries] = useState<Entry[]>([]);
  const [snackQueue, setSnackQueue] = useState<SnackRequest[]>([]);
  const nextId = useRef(1);

  const open = useCallback(
    <T,>(kind: Entry['kind'], render: (close: Close<T>) => ReactNode, dismissible: boolean): Promise<T | undefined> =>
      new Promise((resolve) => {
        const id = nextId.current++;
        setEntries((list) => [...list, { id, kind, dismissible, render: render as Entry['render'], resolve }]);
      }),
    [],
  );

  const close = useCallback((id: number, value: unknown) => {
    setEntries((list) => {
      const entry = list.find((e) => e.id === id);
      entry?.resolve(value);
      return list.filter((e) => e.id !== id);
    });
  }, []);

  const api = useMemo<OverlayApi>(() => {
    const showDialog = <T,>(render: (close: Close<T>) => ReactNode, opts?: { dismissible?: boolean }) =>
      open<T>('dialog', render, opts?.dismissible ?? true);
    return {
      showDialog,
      showSheet: (render, opts) => open('sheet', render, opts?.dismissible ?? true),
      showPage: (render) => open('page', render, false),
      snack: (message, opts) =>
        setSnackQueue((q) => [...q, { id: nextId.current++, message, action: opts?.action, duration: opts?.duration ?? 4000 }]),
      confirm: async (o) =>
        (await showDialog<boolean>((done) => <ConfirmDialog {...o} close={done} />)) === true,
    };
  }, [open]);

  const snack = snackQueue[0];

  return (
    <OverlayContext.Provider value={api}>
      {children}
      <Portal>
        {entries.map((e) =>
          e.kind === 'page' ? (
            <PageFrame key={e.id} onClose={() => close(e.id, undefined)}>
              {e.render((value) => close(e.id, value))}
            </PageFrame>
          ) : e.kind === 'dialog' ? (
            <DialogFrame key={e.id} dismissible={e.dismissible} onDismiss={() => close(e.id, undefined)}>
              {e.render((value) => close(e.id, value))}
            </DialogFrame>
          ) : (
            <SheetFrame key={e.id} dismissible={e.dismissible} onDismiss={() => close(e.id, undefined)}>
              {e.render((value) => close(e.id, value))}
            </SheetFrame>
          ),
        )}
        <Snackbar
          key={snack?.id}
          visible={snack != null}
          duration={snack?.duration}
          onDismiss={() => setSnackQueue((q) => q.slice(1))}
          action={snack?.action}
          wrapperStyle={{ maxWidth: 560, alignSelf: 'center', width: '100%' }}
        >
          {snack?.message ?? ''}
        </Snackbar>
      </Portal>
    </OverlayContext.Provider>
  );
}

/// Inside a page opened with showPage: how its back button closes it.
export const OverlayPageContext = createContext<(() => void) | null>(null);

function PageFrame({ children, onClose }: { children: ReactNode; onClose: () => void }) {
  const { colors } = useAppTheme();
  return (
    <View style={[StyleSheet.absoluteFill, { backgroundColor: colors.surface }]}>
      <OverlayPageContext.Provider value={onClose}>{children}</OverlayPageContext.Provider>
    </View>
  );
}

/// The context a dialog's content is drawn in: its title, body and buttons
/// come from the pieces below.
function DialogFrame({ children, dismissible, onDismiss }: { children: ReactNode; dismissible: boolean; onDismiss: () => void }) {
  const { width } = useWindowDimensions();
  return (
    <Dialog
      visible
      dismissable={dismissible}
      dismissableBackButton={dismissible}
      onDismiss={onDismiss}
      style={{ maxWidth: Math.min(560, width - 32), width: '100%', alignSelf: 'center' }}
    >
      {children}
    </Dialog>
  );
}

function SheetFrame({ children, dismissible, onDismiss }: { children: ReactNode; dismissible: boolean; onDismiss: () => void }) {
  const { colors } = useAppTheme();
  const { width, height } = useWindowDimensions();
  const compact = width < Breakpoints.medium;
  return (
    <View style={StyleSheet.absoluteFill}>
      <Pressable
        accessibilityLabel="Close"
        style={[StyleSheet.absoluteFill, { backgroundColor: colors.backdrop }]}
        onPress={dismissible ? onDismiss : undefined}
      />
      <View
        pointerEvents="box-none"
        style={[StyleSheet.absoluteFill, { justifyContent: compact ? 'flex-end' : 'center', alignItems: 'center' }]}
      >
        <View
          style={{
            width: compact ? '100%' : Math.min(640, width - 48),
            maxHeight: height * (compact ? 0.92 : 0.86),
            backgroundColor: colors.surfaceContainerLow,
            borderTopLeftRadius: 28,
            borderTopRightRadius: 28,
            borderBottomLeftRadius: compact ? 0 : 28,
            borderBottomRightRadius: compact ? 0 : 28,
            overflow: 'hidden',
          }}
        >
          {/* The drag handle, as a cue that this is a sheet. */}
          <View style={{ alignItems: 'center', paddingTop: 12, paddingBottom: 8 }}>
            <View style={{ width: 32, height: 4, borderRadius: 2, backgroundColor: colors.onSurfaceVariant, opacity: 0.4 }} />
          </View>
          {children}
        </View>
      </View>
    </View>
  );
}

/// A sheet's scrolling body, padded like Flutter's sheets.
export function SheetScroll({ children, padding = 16 }: { children: ReactNode; padding?: number }) {
  return (
    <ScrollView contentContainerStyle={{ paddingHorizontal: padding, paddingBottom: 24 }} keyboardShouldPersistTaps="handled">
      {children}
    </ScrollView>
  );
}

function ConfirmDialog({
  title,
  message,
  confirmLabel = 'OK',
  cancelLabel = 'Cancel',
  destructive = false,
  close,
}: ConfirmOptions & { close: Close<boolean> }) {
  const { colors } = useAppTheme();
  return (
    <>
      <Dialog.Title>{title}</Dialog.Title>
      {message != null && (
        <Dialog.Content>{typeof message === 'string' ? <Text variant="bodyMedium">{message}</Text> : message}</Dialog.Content>
      )}
      <Dialog.Actions>
        <Button onPress={() => close(false)}>{cancelLabel}</Button>
        <Button
          mode="contained"
          buttonColor={destructive ? colors.error : undefined}
          textColor={destructive ? colors.onError : undefined}
          onPress={() => close(true)}
        >
          {confirmLabel}
        </Button>
      </Dialog.Actions>
    </>
  );
}
