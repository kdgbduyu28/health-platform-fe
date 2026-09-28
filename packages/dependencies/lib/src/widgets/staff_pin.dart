import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/intake_provider.dart';
import '../providers/supabase_providers.dart';
import 'async_view.dart';

const _pinLength = 4;

/// Asks for the signed-in account's staff PIN; true once it is right.
///
/// [allowSignOut] offers the way out for a forgotten PIN on the locked
/// tablet: signing out ends the hand-off without showing anything, and the
/// staff member signs back in with their password.
Future<bool> showStaffPinDialog(
  BuildContext context, {
  bool allowSignOut = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _VerifyPinDialog(allowSignOut: allowSignOut),
  );
  return ok ?? false;
}

/// Sets (or changes) the signed-in account's staff PIN; true once saved.
Future<bool> showSetStaffPinDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _SetPinDialog(),
  );
  return ok ?? false;
}

/// True when the account has a PIN, asking for one first if it has none —
/// the tablet is not handed over until there is a way to take it back.
Future<bool> ensureStaffPin(BuildContext context, WidgetRef ref) async {
  final bool has;
  try {
    has = await ref.read(hasStaffPinProvider.future);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
    return false;
  }
  if (has) return true;
  if (!context.mounted) return false;
  return showSetStaffPinDialog(context);
}

class _VerifyPinDialog extends ConsumerStatefulWidget {
  const _VerifyPinDialog({required this.allowSignOut});

  final bool allowSignOut;

  @override
  ConsumerState<_VerifyPinDialog> createState() => _VerifyPinDialogState();
}

class _VerifyPinDialogState extends ConsumerState<_VerifyPinDialog> {
  String _pin = '';
  bool _busy = false;
  String? _error;

  Future<void> _onChanged(String pin) async {
    setState(() {
      _pin = pin;
      _error = null;
    });
    if (pin.length < _pinLength) return;
    setState(() => _busy = true);
    try {
      final ok = await ref.read(healthRepositoryProvider).verifyStaffPin(pin);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => _error = 'Wrong PIN');
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Staff PIN', textAlign: TextAlign.center),
      content: _PinPad(
        pin: _pin,
        busy: _busy,
        caption: 'Enter your 4-digit staff PIN.',
        error: _error,
        onChanged: _onChanged,
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (widget.allowSignOut)
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    Navigator.pop(context, false);
                    ref.read(healthRepositoryProvider).signOut();
                  },
            child: const Text('Forgot PIN? Sign out'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _SetPinDialog extends ConsumerStatefulWidget {
  const _SetPinDialog();

  @override
  ConsumerState<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends ConsumerState<_SetPinDialog> {
  String _pin = '';

  /// The first entry, while the second one confirms it.
  String? _first;
  bool _busy = false;
  String? _error;

  Future<void> _onChanged(String pin) async {
    setState(() {
      _pin = pin;
      _error = null;
    });
    if (pin.length < _pinLength) return;

    final first = _first;
    if (first == null) {
      setState(() {
        _first = pin;
        _pin = '';
      });
      return;
    }
    if (first != pin) {
      setState(() {
        _first = null;
        _pin = '';
        _error = 'The PINs did not match. Start again.';
      });
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(healthRepositoryProvider).setStaffPin(pin);
      ref.invalidate(hasStaffPinProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = describeError(e);
          _first = null;
          _pin = '';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_first == null ? 'Set a staff PIN' : 'Confirm your PIN',
          textAlign: TextAlign.center),
      content: _PinPad(
        pin: _pin,
        busy: _busy,
        caption: _first == null
            ? 'You will need it to take the tablet back from a patient. '
                'Keep it to yourself.'
            : 'Enter the same 4 digits again.',
        error: _error,
        onChanged: _onChanged,
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Four dots and a number pad, big enough to hit on a tablet. No text field,
/// so no on-screen keyboard and nothing for the browser to autofill.
class _PinPad extends StatelessWidget {
  const _PinPad({
    required this.pin,
    required this.onChanged,
    required this.caption,
    this.busy = false,
    this.error,
  });

  final String pin;
  final ValueChanged<String> onChanged;
  final String caption;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget key(String label, {IconData? icon, VoidCallback? onTap}) => Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: 72,
            height: 64,
            child: label.isEmpty && icon == null
                ? null
                : FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      textStyle: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w600),
                    ),
                    onPressed: busy ? null : onTap,
                    child: icon == null ? Text(label) : Icon(icon),
                  ),
          ),
        );

    Widget digit(String d) => key(d, onTap: () {
          if (pin.length < _pinLength) onChanged(pin + d);
        });

    return SizedBox(
      width: 260,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(caption,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _pinLength; i++)
                Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < pin.length ? cs.primary : null,
                    border: Border.all(color: cs.primary, width: 2),
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 36,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(error ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.error, fontSize: 13)),
            ),
          ),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [for (final d in row) digit(d)],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              key(''),
              digit('0'),
              key('',
                  icon: Icons.backspace_outlined,
                  onTap: pin.isEmpty
                      ? null
                      : () => onChanged(pin.substring(0, pin.length - 1))),
            ],
          ),
        ],
      ),
    );
  }
}
