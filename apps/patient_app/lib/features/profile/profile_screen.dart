import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:api_sdk/api_sdk.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinic = ref.watch(currentClinicProvider).value;
    final profile = ref.watch(myProfileProvider).value;
    final patient = ref.watch(myPatientProvider).value;
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    // Name and contact come from the person record behind this clinic's chart
    // — what the clinic itself sees. The profile stands in while that loads.
    final displayName = patient?.name ?? profile?.fullName ?? '';
    final initials = patient?.initials ?? profile?.initials ?? '?';
    final phone = patient?.phone ?? profile?.phone ?? '—';
    final email = patient?.email.isNotEmpty == true
        ? patient!.email
        : (profile?.email ?? '—');

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cs.primary, cs.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 48),
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: cs.onPrimary.withAlpha(50),
                      child: Text(
                        initials,
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimary),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      displayName,
                      style: theme.textTheme.titleLarge?.copyWith(
                          color: cs.onPrimary, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      clinic?.name ?? '',
                      style: TextStyle(
                          color: cs.onPrimary.withAlpha(200), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverList.list(
            children: [
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _ProfileTile(
                      icon: Icons.phone_outlined,
                      label: 'Phone',
                      value: phone,
                    ),
                    _ProfileTile(
                      icon: Icons.email_outlined,
                      label: 'Email',
                      value: email,
                    ),
                    if (patient?.age != null)
                      _ProfileTile(
                        icon: Icons.cake_outlined,
                        label: 'Age',
                        value: '${patient!.age} years old',
                      ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/join'),
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('Join another clinic'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit Profile'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      // Signing out clears the session, which drops every RLS
                      // grant with it — the app shell then swaps the router
                      // back to the sign-in screen on its own.
                      onPressed: () =>
                          ref.read(healthRepositoryProvider).signOut(),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red)),
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign Out'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: cs.onPrimaryContainer, size: 20),
      ),
      title: Text(label,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      subtitle: Text(value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
    );
  }
}
