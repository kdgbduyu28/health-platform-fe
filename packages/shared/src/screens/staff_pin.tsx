import { useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Pressable, View } from 'react-native';
import { ActivityIndicator, Button, Dialog, Text } from 'react-native-paper';

import { useCurrentUserId, usePlatform } from '../state/platform';
import { useAppTheme } from '../theme/clinic_theme';
import { describeError } from '../ui/async_view';
import { Icon } from '../ui/icon';
import { type Close, useOverlay } from '../ui/overlay';

const pinLength = 4;

/// The staff PIN dialogs: checking it (taking the tablet back from a
/// patient) and setting it.
export function useStaffPin() {
  const overlay = useOverlay();
  const { repo } = usePlatform();
  const uid = useCurrentUserId();
  const qc = useQueryClient();

  /// Sets (or changes) the signed-in account's staff PIN; true once saved.
  const setPin = async () => (await overlay.showDialog<boolean>((close) => <SetPinDialog close={close} />)) === true;

  return {
    /// Asks for the signed-in account's staff PIN; true once it is right.
    ///
    /// [allowSignOut] offers the way out for a forgotten PIN on the locked
    /// tablet: signing out ends the hand-off without showing anything, and
    /// the staff member signs back in with their password.
    verify: async (allowSignOut = false) =>
      (await overlay.showDialog<boolean>((close) => <VerifyPinDialog close={close} allowSignOut={allowSignOut} />, {
        dismissible: false,
      })) === true,

    setPin,

    /// True when the account has a PIN, asking for one first if it has none
    /// — the tablet is not handed over until there is a way to take it back.
    ensure: async () => {
      let has: boolean;
      try {
        has = await qc.fetchQuery({ queryKey: ['hasStaffPin', uid], queryFn: () => repo.hasStaffPin() });
      } catch (e) {
        overlay.snack(describeError(e));
        return false;
      }
      return has || setPin();
    },
  };
}

function VerifyPinDialog({ close, allowSignOut }: { close: Close<boolean>; allowSignOut: boolean }) {
  const { repo } = usePlatform();
  const [pin, setPin] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onChanged = async (next: string) => {
    setPin(next);
    setError(null);
    if (next.length < pinLength) return;
    setBusy(true);
    try {
      if (await repo.verifyStaffPin(next)) {
        close(true);
        return;
      }
      setError('Wrong PIN');
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
      setPin('');
    }
  };

  return (
    <>
      <Dialog.Title style={{ textAlign: 'center' }}>Staff PIN</Dialog.Title>
      <Dialog.Content>
        <PinPad pin={pin} busy={busy} caption="Enter your 4-digit staff PIN." error={error} onChanged={onChanged} />
      </Dialog.Content>
      <Dialog.Actions style={{ justifyContent: 'space-between' }}>
        {allowSignOut ? (
          <Button
            disabled={busy}
            onPress={() => {
              close(false);
              void repo.signOut();
            }}
          >
            Forgot PIN? Sign out
          </Button>
        ) : (
          <View />
        )}
        <Button disabled={busy} onPress={() => close(false)}>
          Cancel
        </Button>
      </Dialog.Actions>
    </>
  );
}

function SetPinDialog({ close }: { close: Close<boolean> }) {
  const { repo } = usePlatform();
  const qc = useQueryClient();
  const [pin, setPin] = useState('');
  /// The first entry, while the second one confirms it.
  const [first, setFirst] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onChanged = async (next: string) => {
    setPin(next);
    setError(null);
    if (next.length < pinLength) return;
    if (first == null) {
      setFirst(next);
      setPin('');
      return;
    }
    if (first !== next) {
      setFirst(null);
      setPin('');
      setError('The PINs did not match. Start again.');
      return;
    }
    setBusy(true);
    try {
      await repo.setStaffPin(next);
      void qc.invalidateQueries({ queryKey: ['hasStaffPin'] });
      close(true);
    } catch (e) {
      setError(describeError(e));
      setFirst(null);
      setPin('');
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <Dialog.Title style={{ textAlign: 'center' }}>{first == null ? 'Set a staff PIN' : 'Confirm your PIN'}</Dialog.Title>
      <Dialog.Content>
        <PinPad
          pin={pin}
          busy={busy}
          caption={
            first == null
              ? 'You will need it to take the tablet back from a patient. Keep it to yourself.'
              : 'Enter the same 4 digits again.'
          }
          error={error}
          onChanged={onChanged}
        />
      </Dialog.Content>
      <Dialog.Actions>
        <Button disabled={busy} onPress={() => close(false)}>
          Cancel
        </Button>
      </Dialog.Actions>
    </>
  );
}

/// Four dots and a number pad, big enough to hit on a tablet. No text field,
/// so no on-screen keyboard and nothing for the browser to autofill.
function PinPad({
  pin,
  onChanged,
  caption,
  busy,
  error,
}: {
  pin: string;
  onChanged: (pin: string) => void;
  caption: string;
  busy: boolean;
  error: string | null;
}) {
  const { colors } = useAppTheme();
  const key = (label: string, opts: { backspace?: boolean; onPress?: () => void } = {}) => {
    const blank = label === '' && !opts.backspace;
    return (
      <View key={label || (opts.backspace ? 'back' : 'blank')} style={{ width: 72, height: 64, margin: 6 }}>
        {!blank && (
          <Pressable
            onPress={opts.onPress}
            disabled={busy || opts.onPress == null}
            accessibilityLabel={opts.backspace ? 'Delete' : label}
            style={({ pressed }) => ({
              flex: 1,
              borderRadius: 12,
              alignItems: 'center',
              justifyContent: 'center',
              backgroundColor: colors.secondaryContainer,
              opacity: busy || opts.onPress == null ? 0.5 : pressed ? 0.8 : 1,
            })}
          >
            {opts.backspace ? (
              <Icon name="backspace" color={colors.onSecondaryContainer} />
            ) : (
              <Text style={{ fontSize: 24, fontWeight: '600', color: colors.onSecondaryContainer }}>{label}</Text>
            )}
          </Pressable>
        )}
      </View>
    );
  };
  const digit = (d: string) => key(d, { onPress: () => pin.length < pinLength && onChanged(pin + d) });

  return (
    <View style={{ width: 260, alignSelf: 'center', alignItems: 'center' }}>
      <Text style={{ textAlign: 'center', color: colors.onSurfaceVariant }}>{caption}</Text>
      <View style={{ flexDirection: 'row', marginTop: 20 }}>
        {Array.from({ length: pinLength }, (_, i) => (
          <View
            key={i}
            style={{
              width: 18,
              height: 18,
              marginHorizontal: 8,
              borderRadius: 9,
              borderWidth: 2,
              borderColor: colors.primary,
              backgroundColor: i < pin.length ? colors.primary : undefined,
            }}
          />
        ))}
      </View>
      <View style={{ height: 36, justifyContent: 'center' }}>
        {busy ? (
          <ActivityIndicator size={18} />
        ) : (
          <Text style={{ textAlign: 'center', color: colors.error, fontSize: 13 }}>{error ?? ''}</Text>
        )}
      </View>
      {[
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
      ].map((row) => (
        <View key={row[0]} style={{ flexDirection: 'row' }}>
          {row.map(digit)}
        </View>
      ))}
      <View style={{ flexDirection: 'row' }}>
        {key('')}
        {digit('0')}
        {key('', { backspace: true, onPress: pin === '' ? undefined : () => onChanged(pin.slice(0, -1)) })}
      </View>
    </View>
  );
}
