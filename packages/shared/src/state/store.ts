import { useSyncExternalStore } from 'react';

/// A value outside React that components can watch: the signed-in session,
/// the device's preferences, the front desk tablet's hand-off. What Riverpod's
/// `Notifier` was for client-side state; server data lives in React Query.
export type Store<T> = {
  get(): T;
  set(next: T | ((prev: T) => T)): void;
  subscribe(listener: () => void): () => void;
};

export function createStore<T>(initial: T): Store<T> {
  let state = initial;
  const listeners = new Set<() => void>();
  return {
    get: () => state,
    set(next) {
      const value = typeof next === 'function' ? (next as (prev: T) => T)(state) : next;
      if (Object.is(value, state)) return;
      state = value;
      for (const l of [...listeners]) l();
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
}

export function useStore<T>(store: Store<T>): T {
  return useSyncExternalStore(store.subscribe, store.get, store.get);
}
