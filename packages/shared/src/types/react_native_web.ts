// What react-native-web adds to React Native's types: a pointer hovering, a
// keyboard focus ring. The apps run only in a browser, where both are there.

import 'react-native';

declare module 'react-native' {
  interface PressableStateCallbackType {
    readonly hovered?: boolean;
    readonly focused?: boolean;
  }
}

export {};
