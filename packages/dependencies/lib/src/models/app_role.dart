/// Mirrors `public.app_role`. One role per signed-in user, matching the four
/// apps in this workspace. The database — not the client — decides this value:
/// every new signup is created as [patient], and only the service role key can
/// change it.
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
}
