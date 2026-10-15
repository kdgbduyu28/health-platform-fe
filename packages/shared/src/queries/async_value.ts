import type { UseQueryResult } from '@tanstack/react-query';

/// Data that is loading, has failed, or has arrived — Riverpod's `AsyncValue`,
/// which the screens were written around. A refresh that fails after data
/// arrived keeps the data AND carries the error, so a screen can keep showing
/// what it had.
export type AsyncValue<T> = {
  readonly hasValue: boolean;
  readonly value: T | undefined;
  readonly hasError: boolean;
  readonly error: unknown;
  /// Nothing to show yet, and no error.
  readonly isLoading: boolean;
};

export function asyncData<T>(value: T): AsyncValue<T> {
  return { hasValue: true, value, hasError: false, error: null, isLoading: false };
}

export function asyncLoading<T>(): AsyncValue<T> {
  return { hasValue: false, value: undefined, hasError: false, error: null, isLoading: true };
}

export function asyncError<T>(error: unknown): AsyncValue<T> {
  return { hasValue: false, value: undefined, hasError: true, error, isLoading: false };
}

export function fromQuery<T>(q: UseQueryResult<T>): AsyncValue<T> {
  const hasValue = q.data !== undefined;
  return {
    hasValue,
    value: q.data,
    hasError: q.isError,
    error: q.error,
    isLoading: !hasValue && !q.isError,
  };
}

/// The value once it is there; throws otherwise. For after a guard.
export function requireValue<T>(a: AsyncValue<T>): T {
  if (!a.hasValue) throw new Error('AsyncValue has no value yet');
  return a.value as T;
}

/// [fn] applied to the data, keeping loading and error as they are.
export function mapAsync<T, U>(a: AsyncValue<T>, fn: (value: T) => U): AsyncValue<U> {
  if (!a.hasValue) return a as unknown as AsyncValue<U>;
  return { ...a, value: fn(a.value as T) } as AsyncValue<U>;
}

/// Several values combined once every one has arrived; the first error, or
/// loading, otherwise.
export function combineAsync<T extends unknown[]>(
  values: { [K in keyof T]: AsyncValue<T[K]> },
): AsyncValue<T> {
  for (const v of values) if (v.hasError && !v.hasValue) return asyncError(v.error);
  for (const v of values) if (!v.hasValue) return asyncLoading();
  const error = values.find((v) => v.hasError)?.error ?? null;
  return {
    hasValue: true,
    value: values.map((v) => v.value) as T,
    hasError: error != null,
    error,
    isLoading: false,
  };
}
