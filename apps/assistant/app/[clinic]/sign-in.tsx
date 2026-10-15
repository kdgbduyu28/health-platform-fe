import { SignInScreen } from '@health/shared';
import { useLocalSearchParams } from 'expo-router';

export default function SignIn() {
  const { mode } = useLocalSearchParams<{ mode?: string }>();
  return <SignInScreen initialSignUp={mode === 'sign-up'} />;
}
