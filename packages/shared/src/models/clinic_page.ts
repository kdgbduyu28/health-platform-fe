import { Clinic } from './clinic';
import { Doctor } from './doctor';
import { Service } from './service';

type Json = Record<string, any>;

/// What anyone — signed in or not — may see about a clinic: the page at
/// `/:clinic`, and the branding on its sign-in screen.
///
/// Read from `public.clinic_by_slug`, which leaves out the join code, the
/// doctors' accounts, and anything inactive. [clinic] therefore never carries
/// a join code, even for the clinic's own admin.
export class ClinicPage {
  constructor(
    readonly clinic: Clinic,
    readonly services: Service[] = [],
    readonly doctors: Doctor[] = [],
  ) {}

  static fromJson(json: Json): ClinicPage {
    return new ClinicPage(
      Clinic.fromJson(json),
      ((json.services ?? []) as Json[]).map(Service.fromJson),
      ((json.doctors ?? []) as Json[]).map(Doctor.fromJson),
    );
  }
}
