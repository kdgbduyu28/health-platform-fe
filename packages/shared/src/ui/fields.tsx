import { format } from 'date-fns';
import { createElement, type ReactNode, useCallback, useEffect, useRef, useState } from 'react';
import { type KeyboardTypeOptions, Platform, Pressable, ScrollView, type StyleProp, View, type ViewStyle } from 'react-native';
import { Button, Dialog, HelperText, Text, TextInput } from 'react-native-paper';

import { useAppTheme } from '../theme/clinic_theme';
import { formatDay, parseDay } from '../util/dates';
import { Icon, type IconName } from './icon';
import { useOverlay } from './overlay';

/// A text box, styled like the apps' Flutter fields: filled, rounded, the
/// label inside, an error or a hint underneath.
export function TextField({
  label,
  value,
  onChangeText,
  error,
  helperText,
  placeholder,
  secure = false,
  multiline = false,
  minLines,
  keyboardType,
  autoFocus,
  autoComplete,
  autoCapitalize,
  onSubmit,
  icon,
  right,
  disabled = false,
  maxLength,
  style,
  dense = false,
  prefix,
}: {
  label?: string;
  value: string;
  onChangeText: (text: string) => void;
  error?: string | null;
  helperText?: string | null;
  placeholder?: string;
  secure?: boolean;
  multiline?: boolean;
  minLines?: number;
  keyboardType?: KeyboardTypeOptions;
  autoFocus?: boolean;
  autoComplete?: 'email' | 'password' | 'new-password' | 'current-password' | 'name' | 'tel' | 'off' | 'one-time-code' | 'username';
  autoCapitalize?: 'none' | 'sentences' | 'words' | 'characters';
  onSubmit?: () => void;
  icon?: IconName;
  right?: ReactNode;
  disabled?: boolean;
  maxLength?: number;
  style?: StyleProp<ViewStyle>;
  dense?: boolean;
  prefix?: string;
}) {
  const { colors } = useAppTheme();
  const [hidden, setHidden] = useState(true);
  return (
    <View style={style}>
      <TextInput
        mode="outlined"
        label={label}
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        error={!!error}
        secureTextEntry={secure && hidden}
        multiline={multiline}
        numberOfLines={multiline ? minLines ?? 3 : undefined}
        keyboardType={keyboardType}
        autoFocus={autoFocus}
        autoComplete={autoComplete as never}
        autoCapitalize={autoCapitalize}
        onSubmitEditing={onSubmit}
        disabled={disabled}
        maxLength={maxLength}
        dense={dense}
        outlineColor="transparent"
        outlineStyle={{ borderRadius: 12 }}
        style={{ backgroundColor: colors.surfaceContainerHighest, minHeight: multiline ? 24 * (minLines ?? 3) + 32 : undefined }}
        left={
          prefix != null ? (
            <TextInput.Affix text={prefix} />
          ) : icon != null ? (
            <TextInput.Icon icon={icon} />
          ) : undefined
        }
        right={
          secure ? (
            <TextInput.Icon
              icon={hidden ? 'visibility' : 'visibility-off'}
              onPress={() => setHidden((h) => !h)}
              accessibilityLabel={hidden ? 'Show password' : 'Hide password'}
            />
          ) : (
            (right as never)
          )
        }
      />
      {error ? (
        <HelperText type="error" visible>
          {error}
        </HelperText>
      ) : helperText ? (
        <HelperText type="info" visible>
          {helperText}
        </HelperText>
      ) : null}
    </View>
  );
}

/// The style the native inputs below share, matching TextField.
function useNativeInputStyle(error: boolean, disabled: boolean): Record<string, string | number> {
  const { colors, fonts } = useAppTheme();
  return {
    width: '100%',
    boxSizing: 'border-box',
    minHeight: 56,
    padding: '22px 14px 8px',
    borderRadius: 12,
    border: error ? `2px solid ${colors.error}` : '1px solid transparent',
    outline: 'none',
    background: colors.surfaceContainerHighest,
    color: disabled ? colors.onSurfaceDisabled : colors.onSurface,
    fontFamily: fonts.bodyLarge.fontFamily,
    fontSize: fonts.bodyLarge.fontSize,
    colorScheme: 'inherit',
    appearance: 'none',
    cursor: disabled ? 'default' : 'pointer',
  };
}

/// A native form control with TextField's floating label and error.
function NativeFieldFrame({
  label,
  error,
  helperText,
  children,
  style,
  trailing,
}: {
  label?: string;
  error?: string | null;
  helperText?: string | null;
  children: ReactNode;
  style?: StyleProp<ViewStyle>;
  trailing?: IconName;
}) {
  const { colors } = useAppTheme();
  return (
    <View style={style}>
      <View>
        {children}
        {label != null && (
          <Text
            pointerEvents="none"
            numberOfLines={1}
            style={{ position: 'absolute', left: 14, top: 6, right: 40, fontSize: 12, color: error ? colors.error : colors.onSurfaceVariant }}
          >
            {label}
          </Text>
        )}
        {trailing != null && (
          // Not hit-testable, so the native control underneath keeps the click.
          <View pointerEvents="none" style={{ position: 'absolute', right: 10, top: 16 }}>
            <Icon name={trailing} size={24} color={colors.onSurfaceVariant} />
          </View>
        )}
      </View>
      {error ? (
        <HelperText type="error" visible>
          {error}
        </HelperText>
      ) : helperText ? (
        <HelperText type="info" visible>
          {helperText}
        </HelperText>
      ) : null}
    </View>
  );
}

/// The browser's own controls (`<select>`, date and time inputs) exist only
/// on the web. On a phone each field below is a tap that opens a dialog.
const onWeb = Platform.OS === 'web';

/// On a phone: the field's current text, tapped to pick a new value.
function TapField({
  label,
  text,
  placeholder,
  error,
  disabled,
  onPress,
}: {
  label?: string;
  text: string | null;
  placeholder?: string;
  error: boolean;
  disabled: boolean;
  onPress: () => void;
}) {
  const { colors, fonts } = useAppTheme();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      disabled={disabled}
      onPress={onPress}
      style={{
        minHeight: 56,
        justifyContent: 'center',
        paddingTop: label == null ? 8 : 22,
        paddingBottom: 8,
        paddingLeft: 14,
        paddingRight: 40,
        borderRadius: 12,
        borderWidth: error ? 2 : 1,
        borderColor: error ? colors.error : 'transparent',
        backgroundColor: colors.surfaceContainerHighest,
      }}
    >
      <Text
        numberOfLines={1}
        style={{
          fontSize: fonts.bodyLarge.fontSize,
          color: disabled ? colors.onSurfaceDisabled : text == null ? colors.onSurfaceVariant : colors.onSurface,
        }}
      >
        {text ?? placeholder ?? ''}
      </Text>
    </Pressable>
  );
}

const choiceRow = 48;

/// A list to pick one line from, scrolled to the current one: the phone's
/// stand-in for a `<select>` and for a time picker.
function ChoiceDialog({
  title,
  labels,
  disabled,
  selected,
  onDone,
  onCancel,
}: {
  title?: string;
  labels: readonly string[];
  disabled?: readonly boolean[];
  selected: number;
  onDone: (index: number) => void;
  onCancel: () => void;
}) {
  const { colors } = useAppTheme();
  const list = useRef<ScrollView | null>(null);
  return (
    <>
      {title != null && <Dialog.Title>{title}</Dialog.Title>}
      <Dialog.ScrollArea style={{ maxHeight: 420, paddingHorizontal: 0 }}>
        <ScrollView
          ref={list}
          onLayout={() => selected > 2 && list.current?.scrollTo({ y: (selected - 2) * choiceRow, animated: false })}
        >
          {labels.map((l, i) => {
            const off = disabled?.[i] === true;
            const on = i === selected;
            return (
              <Pressable
                key={i}
                disabled={off}
                onPress={() => onDone(i)}
                style={{ height: choiceRow, flexDirection: 'row', alignItems: 'center', gap: 16, paddingHorizontal: 24 }}
              >
                <Icon
                  name={on ? 'radio-button-checked' : 'radio-button-unchecked'}
                  size={20}
                  color={off ? colors.onSurfaceDisabled : on ? colors.primary : colors.onSurfaceVariant}
                />
                <Text numberOfLines={1} style={{ flex: 1, color: off ? colors.onSurfaceDisabled : colors.onSurface }}>
                  {l}
                </Text>
              </Pressable>
            );
          })}
        </ScrollView>
      </Dialog.ScrollArea>
      <Dialog.Actions>
        <Button onPress={onCancel}>Cancel</Button>
      </Dialog.Actions>
    </>
  );
}

/// Times of day every [step] minutes as `HH:MM`, with [current] added if it
/// falls between them, and how each reads ("9:30 AM").
function timeChoices(step: number, current: string | null): { values: string[]; labels: string[] } {
  const values: string[] = [];
  for (let m = 0; m < 24 * 60; m += Math.max(1, step)) {
    values.push(`${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`);
  }
  if (current != null && !values.includes(current)) {
    values.push(current);
    values.sort();
  }
  return { values, labels: values.map(timeLabel) };
}

function timeLabel(hhmm: string): string {
  const [h, m] = hhmm.split(':').map(Number);
  return format(new Date(2000, 0, 1, h, m), 'h:mm a');
}

export type SelectOption<T> = { value: T; label: string; disabled?: boolean };

/// A drop-down: the browser's own `<select>`, which every device already
/// knows how to show well (a wheel on a phone, a list on a desktop).
export function SelectField<T extends string | number>({
  label,
  value,
  options,
  onChange,
  error,
  helperText,
  disabled = false,
  placeholder,
  style,
}: {
  label?: string;
  value: T | null;
  options: readonly SelectOption<T>[];
  onChange: (value: T) => void;
  error?: string | null;
  helperText?: string | null;
  disabled?: boolean;
  /// Shown, and not pickable, while nothing is chosen.
  placeholder?: string;
  style?: StyleProp<ViewStyle>;
}) {
  const inputStyle = useNativeInputStyle(!!error, disabled);
  const overlay = useOverlay();
  const index = value == null ? -1 : options.findIndex((o) => o.value === value);
  if (!onWeb) {
    const pick = async () => {
      const i = await overlay.showDialog<number>((close) => (
        <ChoiceDialog
          title={label}
          labels={options.map((o) => o.label)}
          disabled={options.map((o) => o.disabled === true)}
          selected={index}
          onDone={close}
          onCancel={() => close(-1)}
        />
      ));
      const o = i == null || i < 0 ? undefined : options[i];
      if (o) onChange(o.value);
    };
    return (
      <NativeFieldFrame label={label} error={error} helperText={helperText} style={style} trailing="arrow-drop-down">
        <TapField
          label={label}
          text={index === -1 ? null : options[index].label}
          placeholder={placeholder}
          error={!!error}
          disabled={disabled}
          onPress={() => void pick()}
        />
      </NativeFieldFrame>
    );
  }
  return (
    <NativeFieldFrame label={label} error={error} helperText={helperText} style={style} trailing="arrow-drop-down">
      {createElement(
        'select',
        {
          value: index === -1 ? '' : String(index),
          disabled,
          'aria-label': label,
          onChange: (e: { target: { value: string } }) => {
            const o = options[Number(e.target.value)];
            if (o) onChange(o.value);
          },
          style: { ...inputStyle, paddingRight: 40 },
        },
        index === -1 && createElement('option', { value: '', disabled: true }, placeholder ?? ''),
        ...options.map((o, i) => createElement('option', { key: i, value: String(i), disabled: o.disabled }, o.label)),
      )}
    </NativeFieldFrame>
  );
}

/// A calendar day, picked with the browser's date picker.
export function DateField({
  label,
  value,
  onChange,
  min,
  max,
  error,
  helperText,
  disabled = false,
  style,
}: {
  label?: string;
  value: Date | null;
  onChange: (value: Date | null) => void;
  min?: Date | null;
  max?: Date | null;
  error?: string | null;
  helperText?: string | null;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
}) {
  const inputStyle = useNativeInputStyle(!!error, disabled);
  const pickDay = useDatePicker();
  if (!onWeb) {
    const pick = async () => {
      const day = await pickDay({ initial: value, first: min, last: max, title: label });
      if (day != null) onChange(day);
    };
    return (
      <NativeFieldFrame label={label} error={error} helperText={helperText} style={style} trailing="calendar-today">
        <TapField
          label={label}
          text={value == null ? null : format(value, 'MMM d, y')}
          error={!!error}
          disabled={disabled}
          onPress={() => void pick()}
        />
      </NativeFieldFrame>
    );
  }
  return (
    <NativeFieldFrame label={label} error={error} helperText={helperText} style={style}>
      {createElement('input', {
        type: 'date',
        value: value == null ? '' : formatDay(value),
        min: min == null ? undefined : formatDay(min),
        max: max == null ? undefined : formatDay(max),
        disabled,
        'aria-label': label,
        onChange: (e: { target: { value: string } }) => onChange(e.target.value === '' ? null : parseDay(e.target.value)),
        style: inputStyle,
      })}
    </NativeFieldFrame>
  );
}

/// A time of day as `HH:MM`, picked with the browser's time picker.
export function TimeField({
  label,
  value,
  onChange,
  error,
  disabled = false,
  step,
  style,
}: {
  label?: string;
  value: string | null;
  onChange: (value: string | null) => void;
  error?: string | null;
  disabled?: boolean;
  /// Minutes between the picker's choices, where the browser honours it.
  step?: number;
  style?: StyleProp<ViewStyle>;
}) {
  const inputStyle = useNativeInputStyle(!!error, disabled);
  const pickTime = useTimePicker();
  if (!onWeb) {
    const pick = async () => {
      const time = await pickTime({ initial: value, title: label, step });
      if (time != null) onChange(time);
    };
    return (
      <NativeFieldFrame label={label} error={error} style={style} trailing="schedule">
        <TapField label={label} text={value == null ? null : timeLabel(value)} error={!!error} disabled={disabled} onPress={() => void pick()} />
      </NativeFieldFrame>
    );
  }
  return (
    <NativeFieldFrame label={label} error={error} style={style}>
      {createElement('input', {
        type: 'time',
        value: value ?? '',
        step: step == null ? undefined : step * 60,
        disabled,
        'aria-label': label,
        onChange: (e: { target: { value: string } }) => onChange(e.target.value === '' ? null : e.target.value.slice(0, 5)),
        style: inputStyle,
      })}
    </NativeFieldFrame>
  );
}

/// Asks for a day in a small dialog: Flutter's `showDatePicker`. Null if
/// cancelled. With [selectable], a month grid where only those days can be
/// picked (a doctor's working days); otherwise the browser's own picker.
export function useDatePicker(): (opts: {
  initial?: Date | null;
  first?: Date | null;
  last?: Date | null;
  title?: string;
  selectable?: (day: Date) => boolean;
}) => Promise<Date | null> {
  const overlay = useOverlay();
  return useCallback(
    async (opts) =>
      (await overlay.showDialog<Date | null>((close) =>
        opts.selectable || !onWeb ? (
          <MonthGridDialog
            title={opts.title ?? 'Pick a day'}
            initial={opts.initial ?? null}
            first={opts.first ?? null}
            last={opts.last ?? null}
            selectable={opts.selectable ?? (() => true)}
            years={!onWeb}
            onDone={(d) => close(d)}
            onCancel={() => close(null)}
          />
        ) : (
        <PickerDialog
          title={opts.title ?? 'Pick a day'}
          type="date"
          initial={opts.initial == null ? '' : formatDay(opts.initial)}
          min={opts.first == null ? undefined : formatDay(opts.first)}
          max={opts.last == null ? undefined : formatDay(opts.last)}
          onDone={(v) => close(v === '' ? null : parseDay(v))}
          onCancel={() => close(null)}
        />
        ),
      )) ?? null,
    [overlay],
  );
}

const weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// A month of days to tap, Monday first, with only [selectable] days (inside
/// [first] … [last]) enabled.
function MonthGridDialog({
  title,
  initial,
  first,
  last,
  selectable,
  years = false,
  onDone,
  onCancel,
}: {
  title: string;
  initial: Date | null;
  first: Date | null;
  last: Date | null;
  selectable: (day: Date) => boolean;
  /// Buttons that jump a year, for days far off (a birthday).
  years?: boolean;
  onDone: (day: Date) => void;
  onCancel: () => void;
}) {
  const { colors } = useAppTheme();
  const start = initial ?? new Date();
  const [month, setMonth] = useState(new Date(start.getFullYear(), start.getMonth(), 1));
  const [picked, setPicked] = useState<Date | null>(initial);
  const min = first == null ? null : new Date(first.getFullYear(), first.getMonth(), first.getDate()).getTime();
  const max = last == null ? null : new Date(last.getFullYear(), last.getMonth(), last.getDate()).getTime();
  const enabled = (d: Date) => (min == null || d.getTime() >= min) && (max == null || d.getTime() <= max) && selectable(d);

  const lead = (month.getDay() + 6) % 7; // Monday first
  const daysIn = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
  const cells: (Date | null)[] = [
    ...Array.from({ length: lead }, () => null),
    ...Array.from({ length: daysIn }, (_, i) => new Date(month.getFullYear(), month.getMonth(), i + 1)),
  ];
  while (cells.length % 7 !== 0) cells.push(null);
  const canBack = min == null || new Date(month.getFullYear(), month.getMonth(), 0).getTime() >= min;
  const canNext = max == null || new Date(month.getFullYear(), month.getMonth() + 1, 1).getTime() <= max;
  const canBackYear = min == null || new Date(month.getFullYear(), month.getMonth() - 11, 0).getTime() >= min;
  const canNextYear = max == null || new Date(month.getFullYear() + 1, month.getMonth(), 1).getTime() <= max;
  const label = month.toLocaleDateString('en-US', { month: 'long', year: 'numeric' });

  return (
    <>
      <Dialog.Title>{title}</Dialog.Title>
      <Dialog.Content>
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <Text variant="titleMedium" style={{ flex: 1 }}>
            {label}
          </Text>
          {years && (
            <Button compact disabled={!canBackYear} onPress={() => setMonth(new Date(month.getFullYear() - 1, month.getMonth(), 1))}>
              <Icon name="keyboard-double-arrow-left" size={22} color={canBackYear ? colors.primary : colors.onSurfaceDisabled} />
            </Button>
          )}
          <Button compact disabled={!canBack} onPress={() => setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1))}>
            <Icon name="chevron-left" size={22} color={canBack ? colors.primary : colors.onSurfaceDisabled} />
          </Button>
          <Button compact disabled={!canNext} onPress={() => setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1))}>
            <Icon name="chevron-right" size={22} color={canNext ? colors.primary : colors.onSurfaceDisabled} />
          </Button>
          {years && (
            <Button compact disabled={!canNextYear} onPress={() => setMonth(new Date(month.getFullYear() + 1, month.getMonth(), 1))}>
              <Icon name="keyboard-double-arrow-right" size={22} color={canNextYear ? colors.primary : colors.onSurfaceDisabled} />
            </Button>
          )}
        </View>
        <View style={{ flexDirection: 'row', marginTop: 8 }}>
          {weekdayInitials.map((d, i) => (
            <Text key={i} style={{ flex: 1, textAlign: 'center', color: colors.onSurfaceVariant, fontSize: 12 }}>
              {d}
            </Text>
          ))}
        </View>
        {Array.from({ length: cells.length / 7 }, (_, row) => (
          <View key={row} style={{ flexDirection: 'row' }}>
            {cells.slice(row * 7, row * 7 + 7).map((d, i) => {
              if (d == null) return <View key={i} style={{ flex: 1, height: 40 }} />;
              const on = enabled(d);
              const isPicked = picked != null && d.toDateString() === picked.toDateString();
              const isToday = d.toDateString() === new Date().toDateString();
              return (
                <View key={i} style={{ flex: 1, height: 40, alignItems: 'center', justifyContent: 'center' }}>
                  <Pressable
                    disabled={!on}
                    onPress={() => setPicked(d)}
                    accessibilityLabel={d.toDateString()}
                    style={{
                      width: 36,
                      height: 36,
                      borderRadius: 18,
                      alignItems: 'center',
                      justifyContent: 'center',
                      backgroundColor: isPicked ? colors.primary : 'transparent',
                      borderWidth: isToday && !isPicked ? 1 : 0,
                      borderColor: colors.primary,
                    }}
                  >
                    <Text style={{ color: isPicked ? colors.onPrimary : on ? colors.onSurface : colors.onSurfaceDisabled }}>{d.getDate()}</Text>
                  </Pressable>
                </View>
              );
            })}
          </View>
        ))}
      </Dialog.Content>
      <Dialog.Actions>
        <Button onPress={onCancel}>Cancel</Button>
        <Button mode="contained" disabled={picked == null} onPress={() => picked && onDone(picked)}>
          OK
        </Button>
      </Dialog.Actions>
    </>
  );
}

/// Asks for a time of day, as `HH:MM`: Flutter's `showTimePicker`. Null if
/// cancelled.
export function useTimePicker(): (opts: { initial?: string | null; title?: string; step?: number }) => Promise<string | null> {
  const overlay = useOverlay();
  return useCallback(
    async (opts) =>
      (await overlay.showDialog<string | null>((close) => {
        if (!onWeb) {
          const { values, labels } = timeChoices(opts.step ?? 15, opts.initial ?? null);
          return (
            <ChoiceDialog
              title={opts.title ?? 'Pick a time'}
              labels={labels}
              selected={opts.initial == null ? values.indexOf('09:00') : values.indexOf(opts.initial)}
              onDone={(i) => close(values[i])}
              onCancel={() => close(null)}
            />
          );
        }
        return (
          <PickerDialog
            title={opts.title ?? 'Pick a time'}
            type="time"
            initial={opts.initial ?? ''}
            onDone={(v) => close(v === '' ? null : v.slice(0, 5))}
            onCancel={() => close(null)}
          />
        );
      })) ?? null,
    [overlay],
  );
}

function PickerDialog({
  title,
  type,
  initial,
  min,
  max,
  onDone,
  onCancel,
}: {
  title: string;
  type: 'date' | 'time';
  initial: string;
  min?: string;
  max?: string;
  onDone: (value: string) => void;
  onCancel: () => void;
}) {
  const [value, setValue] = useState(initial);
  const ref = useRef<HTMLInputElement | null>(null);
  const style = useNativeInputStyle(false, false);
  useEffect(() => {
    // Opens the browser's picker straight away where it allows that.
    const input = ref.current;
    input?.focus();
    try {
      input?.showPicker?.();
    } catch {
      // Needs a click in some browsers; the field is there to click.
    }
  }, []);
  return (
    <>
      <Dialog.Title>{title}</Dialog.Title>
      <Dialog.Content>
        {createElement('input', {
          ref,
          type,
          value,
          min,
          max,
          onChange: (e: { target: { value: string } }) => setValue(e.target.value),
          onKeyDown: (e: { key: string }) => {
            if (e.key === 'Enter' && value !== '') onDone(value);
          },
          style: { ...style, padding: '14px' },
        })}
      </Dialog.Content>
      <Dialog.Actions>
        <Button onPress={onCancel}>Cancel</Button>
        <Button mode="contained" disabled={value === ''} onPress={() => onDone(value)}>
          OK
        </Button>
      </Dialog.Actions>
    </>
  );
}

/// What a form's fields say, and which are wrong: the part of Flutter's
/// `Form` + validators the screens lean on.
export function useForm<T extends Record<string, string>>(initial: T) {
  const [values, setValues] = useState<T>(initial);
  const [errors, setErrors] = useState<Partial<Record<keyof T, string | null>>>({});
  return {
    values,
    errors,
    set: (name: keyof T) => (text: string) => {
      setValues((v) => ({ ...v, [name]: text }));
      if (errors[name]) setErrors((e) => ({ ...e, [name]: null }));
    },
    setValues,
    setErrors,
    /// Runs [rules] over every field, shows what failed, and answers whether
    /// all passed.
    validate(rules: Partial<Record<keyof T, (value: string, all: T) => string | null | undefined>>): boolean {
      const next: Partial<Record<keyof T, string | null>> = {};
      let ok = true;
      for (const key of Object.keys(rules) as (keyof T)[]) {
        const message = rules[key]!(values[key], values) ?? null;
        next[key] = message;
        if (message) ok = false;
      }
      setErrors(next);
      return ok;
    },
  };
}
