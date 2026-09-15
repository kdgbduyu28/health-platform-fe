/// Mirrors `public.app_role`, and names the four apps.
///
/// A role is held per clinic, on `clinic_memberships` — never per account — so
/// one person can be an admin at one clinic and a doctor at another. [patient]
/// is never a membership role: a patient is recognised by holding a chart at
/// the clinic instead. The database, not the client, decides all of this.
enum AppRole {
  patient,
  doctor,
  assistant,
  admin;

  static AppRole fromWire(String value) => AppRole.values.byName(value);

  String get wire => name;

  bool get isStaff => this != AppRole.patient;

  String get displayName => switch (this) {
        AppRole.patient => 'Patient',
        AppRole.doctor => 'Doctor',
        AppRole.assistant => 'Assistant',
        AppRole.admin => 'Administrator',
      };

  /// Whether a membership with [membershipRole] lets its holder use the app
  /// named by this role.
  ///
  /// Admins may run the front desk — the database lets them register walk-ins
  /// too — so the assistant app accepts them. The doctor app does not: it is
  /// built around the signed-in doctor's own roster row.
  bool isGrantedBy(AppRole membershipRole) => switch (this) {
        AppRole.patient => false,
        AppRole.doctor => membershipRole == AppRole.doctor,
        AppRole.assistant =>
          membershipRole == AppRole.assistant || membershipRole == AppRole.admin,
        AppRole.admin => membershipRole == AppRole.admin,
      };
}
