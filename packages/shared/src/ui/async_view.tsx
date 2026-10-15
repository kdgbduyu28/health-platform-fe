import { AuthError } from '@supabase/supabase-js';
import type { ReactNode } from 'react';
import { View } from 'react-native';
import { ActivityIndicator, Button, Text } from 'react-native-paper';

import { DatabaseError } from '../data/health_repository';
import type { AsyncValue } from '../queries/async_value';
import { useAppTheme } from '../theme/clinic_theme';
import { Icon } from './icon';

/// Renders an AsyncValue with consistent loading and error states.
///
/// Routing every screen through this keeps those two states from being
/// quietly dropped — an RLS denial or a paused free-tier project surfaces as
/// a visible, retryable error rather than an empty list that looks like "no
/// appointments".
export function AsyncView<T>({
  value,
  children,
  onRetry,
  padded = false,
}: {
  value: AsyncValue<T>;
  children: (data: T) => ReactNode;
  onRetry?: () => void;
  /// Loading inside a scrolling page rather than filling the screen.
  padded?: boolean;
}) {
  if (value.hasValue) return <>{children(value.value as T)}</>;
  if (value.hasError) return <ErrorView error={value.error} onRetry={onRetry} />;
  return <Loading padded={padded} />;
}

export function Loading({ padded = false }: { padded?: boolean }) {
  return (
    <View style={padded ? { padding: 48, alignItems: 'center' } : { flex: 1, alignItems: 'center', justifyContent: 'center' }}>
      <ActivityIndicator />
    </View>
  );
}

export function ErrorView({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ padding: 32, alignItems: 'center', alignSelf: 'center', maxWidth: 520 }}>
      <Icon name="cloud-off" size={48} color={colors.error} />
      <Text variant="titleMedium" style={{ marginTop: 16 }}>
        Could not load data
      </Text>
      <Text style={{ marginTop: 6, textAlign: 'center', color: colors.onSurfaceVariant, fontSize: 13 }}>
        {describeError(error)}
      </Text>
      {onRetry && (
        <Button mode="outlined" icon="refresh" onPress={onRetry} style={{ marginTop: 20 }}>
          Try again
        </Button>
      )}
    </View>
  );
}

/// Turns Supabase's errors into something a clinic receptionist could act
/// on, instead of a raw stack trace.
export function describeError(error: unknown): string {
  // The database functions (join_clinic, invite_staff, book_walk_in, …)
  // raise messages written for the person using the app: "that clinic code
  // is not valid", "a clinic must keep at least one admin". Plain RAISE
  // EXCEPTION arrives as SQLSTATE P0001 — show its message, not the wrapper.
  if (error instanceof DatabaseError && error.code === 'P0001') return error.message;
  // Supabase Auth's messages are already sentences ("Invalid login
  // credentials").
  if (error instanceof AuthError) {
    if (error.message.includes('expired or is invalid')) {
      return 'That code is wrong or has expired. Request a new one.';
    }
    // Turnstile's token was missing, spent or refused by Cloudflare.
    if (error.code === 'captcha_failed' || error.message.toLowerCase().includes('captcha')) {
      return 'The security check did not pass. Wait for it to finish, then try again.';
    }
    return error.message;
  }
  const text =
    error instanceof DatabaseError
      ? [error.message, error.details, error.code].filter(Boolean).join(' ')
      : error instanceof Error
        ? error.message
        : typeof error === 'object' && error != null && 'message' in error
          ? String((error as { message: unknown }).message)
          : String(error);
  if (text.includes('Failed to fetch') || text.includes('NetworkError') || text.includes('Load failed')) {
    return 'No connection. Check your network and try again.';
  }
  // The partial unique index on (doctor_id, scheduled_at) is what makes
  // concurrent bookings safe, so losing that race is an ordinary outcome for
  // a patient — not an error to dump raw.
  if (text.includes('appointments_no_double_booking') || text.includes('duplicate key')) {
    return 'That time slot has just been taken. Please pick another.';
  }
  if (text.includes('row-level security')) return 'You do not have permission to do that.';
  if (text.includes('JWT') || text.includes('token is expired')) {
    return 'Your session has expired. Please sign in again.';
  }
  return error instanceof DatabaseError ? error.message : text.replace(/^Error: /, '');
}
