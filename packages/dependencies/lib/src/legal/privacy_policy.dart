import 'legal_document.dart';

/// The platform's Privacy Policy, under the Data Privacy Act of 2012
/// (RA 10173): shown before anything is collected, and in Settings.
///
/// It describes what the system actually does — keep it in step when a
/// feature changes what is collected, who sees it or where it goes, and bump
/// [version]. Each clinic's consent to health information is separate: the
/// patient information form asks for it (patient_intake_form.dart).
abstract final class PrivacyPolicy {
  static const version = '2026-09-30';

  static const _op = LegalContact.operator;
  static const _email = LegalContact.email;

  static const document = LegalDocument(
    id: 'privacy',
    title: 'Privacy Policy',
    version: version,
    intro: 'This Privacy Policy explains how personal information is handled '
        'in this clinic platform — the Patient, Doctor, Assistant and Admin '
        'apps — under the Data Privacy Act of 2012 (Republic Act No. 10173), '
        'its Implementing Rules and Regulations, and the rules of the '
        'National Privacy Commission (NPC).',
    sections: [
      LegalSection('Who we are', [
        'The platform is operated by $_op ("we", "us"). You can reach us, '
            'and our Data Protection Officer, at $_email.',
        'We have two roles. For your account — your name, email, password '
            'and sign-in records — we are the personal information '
            'controller. For your records at a clinic — your visits, medical '
            'history, dental chart and bills — that clinic is the personal '
            'information controller, and we process those records on its '
            'behalf.',
        'Each clinic decides what it asks of its patients and is responsible '
            'for the care it gives. Questions about your records at a clinic '
            'can go to that clinic or to us; we will pass them on.',
      ]),
      LegalSection('What we collect', [
        '- Your account: full name, email address and password. The password '
            'is stored only in scrambled (hashed) form; no one, including us, '
            'can read it.',
        '- The patient information form, when you join a clinic or visit its '
            'front desk: name, birthday, sex, address, occupation, mobile '
            'number, email, emergency contact, the medicines you take, '
            'allergies, medical conditions, and the name you sign with. When '
            'a parent or guardian fills it in: their name, relationship to '
            'you, phone and email.',
        '- Your visits: bookings, dates and times, the doctor and service, '
            'check-in and completion, cancellations and no-shows, doctors\' '
            'clinical notes, and notes written to you.',
        '- Your dental chart, at dental clinics: the condition of each tooth, '
            'and the work planned and done.',
        '- Billing: bills and their items, prices and discounts, and payments '
            'with how they were made (cash, GCash, BPI, BDO or QR Ph). The '
            'apps only record payments; they do not handle money or card '
            'details.',
        '- Clinic staff: name, email, role and clinic; for doctors, their '
            'profile, schedule and time off; a tablet PIN, stored only in '
            'hashed form.',
        '- Security and records of activity: sign-in times, IP address, and '
            'browser and device details in our providers\' logs; the '
            'automated check that tells people from bots on sign-in; a log of '
            'who changed a clinic\'s records and when; and a log of data '
            'exports.',
        '- Notifications and calendar: your in-app notifications and which '
            'kinds you have turned off; if you turn on push notifications, '
            'your browser\'s push address; if you subscribe to your visits in '
            'a calendar app, a private link.',
        'Health information, and details such as your age and sex, are '
            'sensitive personal information under the law, and we treat them '
            'with the extra care the law requires. Clinics may also bring in '
            'records they already hold on paper or in spreadsheets.',
      ]),
      LegalSection('How we use it, and why we may', [
        '- To create and run your account and let you join clinics, because '
            'you asked us to (RA 10173, Sec. 12(b)).',
        '- To book, confirm, remind you of, reschedule and record your visits, '
            'keep your chart and bill you: for your medical care by the '
            'clinic (Sec. 13(f)) and with the consent you give on its patient '
            'information form (Sec. 13(a)).',
        '- To send you reminders and notifications, unless you turn them '
            'off.',
        '- To keep the platform and your records secure — stopping misuse, '
            'protecting accounts, and keeping a record of changes — which the '
            'law requires of us (Sec. 20) and which is in everyone\'s '
            'legitimate interest (Sec. 12(f)).',
        '- To meet legal duties, lawful orders, and the clinics\' duties to '
            'keep medical and billing records (Sec. 12(c)).',
        'We do not sell your information, use it for advertising, or build '
            'marketing profiles. No decision about you is made by automated '
            'means alone. We will not use your information for any new '
            'purpose without telling you first and, where the law requires, '
            'asking for your consent.',
      ]),
      LegalSection('Who can see it', [
        '- You: your account, your information form, your visits and notes '
            'written to you, your dental chart, and your bills.',
        '- Front desk staff: the clinic\'s patient list, information forms '
            '(including the medical answers, so they can prepare your visit), '
            'bookings and bills — but not doctors\' clinical notes.',
        '- Doctors: their clinic\'s patients, forms, visits, dental charts '
            'and clinical notes.',
        '- Clinic administrators: everything at their clinic, including '
            'clinical notes, the ledger and the record of changes. A branch '
            'administrator sees only their branch.',
        '- Other clinics: never your records at a clinic. If you are a '
            'patient at more than one clinic on the platform, your basic '
            'details (name, birthday, sex, contact details, address, '
            'occupation and emergency contact) are kept '
            'once and shared between the clinics you have joined, so a '
            'correction at one reaches the others. Your visits, forms, notes, '
            'charts and bills stay separate at each clinic.',
        '- Us: only to run, support and secure the platform, or when the law '
            'requires it.',
        'These limits are enforced by the database itself, not only by the '
            'apps.',
      ]),
      LegalSection('Service providers, and where your information is kept', [
        'We use a small number of providers to run the platform. Each '
            'handles your information only to provide its service to us, and '
            'is bound to protect it.',
        '- Supabase: our database and sign-in service. Your information is '
            'stored in its data centre in Mumbai, India.',
        '- Cloudflare: hosts the apps and runs the security check on '
            'sign-in, sign-up and password reset.',
        '- Our email provider: sends account emails, such as password reset '
            'codes.',
        '- Your browser\'s push service (for example Google, Mozilla, Apple '
            'or Microsoft), only if you turn on push notifications, to '
            'deliver them.',
        '- Google Calendar or your own calendar app, only if you add a visit '
            'to it or subscribe to your visits. To protect your privacy, '
            'calendar entries leave out the service you are seeing the '
            'doctor for.',
        'Because your information is stored outside the Philippines, we '
            'remain responsible for it wherever it is kept (Sec. 21), and '
            'choose providers that protect it to the standard the law '
            'requires. We may disclose information when the law or a lawful '
            'order requires it.',
      ]),
      LegalSection('How long we keep it', [
        '- Your account: until you ask us to close it.',
        '- Medical, dental and billing records: kept by the clinic for as '
            'long as the rules on medical and tax records require, even after '
            'your account is closed; then deleted or anonymised.',
        '- In-app notifications: deleted automatically after 90 days.',
        '- The record of changes to clinic records: kept as long as the '
            'records it describes.',
        '- Records of your agreement to this policy and the Terms: as long '
            'as your account.',
      ]),
      LegalSection('How we protect it', [
        '- Your information is encrypted in transit and when stored.',
        '- Every record is tied to its clinic, and the database decides who '
            'may read or change it by their role there.',
        '- Clinical notes are for doctors and administrators only.',
        '- Passwords and tablet PINs are stored only in hashed form; repeated '
            'wrong PINs lock the tablet.',
        '- An automated check stands in the way of bots trying to guess '
            'passwords.',
        '- Changes to patient and clinic records are logged with who made '
            'them and when, and data exports are logged.',
        '- A tablet handed to a patient shows only the information form until '
            'a staff member unlocks it with their PIN.',
        'If a breach puts your information at real risk, we and the clinic '
            'will notify the National Privacy Commission and you within 72 '
            'hours of knowing about it, as the NPC requires.',
      ]),
      LegalSection('Your rights', [
        'Under the Data Privacy Act you have the right to:',
        '- be informed of how your information is collected and used;',
        '- see your information and get a copy of it;',
        '- have wrong or incomplete information corrected;',
        '- object to its use, or withdraw your consent;',
        '- have it blocked, removed or destroyed where the law allows;',
        '- receive it in a commonly used electronic format, to take to '
            'someone else;',
        '- be compensated for damage caused by its misuse; and',
        '- complain to the National Privacy Commission.',
        'To use any of these, email $_email or ask your clinic. We may need '
            'to confirm who you are first. Some things you can change '
            'yourself in the app.',
        'If you withdraw your consent, a clinic may still keep the records '
            'it must keep by law, and may not be able to treat you safely '
            'without the information it needs.',
        'You can complain to the National Privacy Commission at '
            'privacy.gov.ph.',
      ]),
      LegalSection('Children', [
        'A patient under 18 should have a parent or guardian create the '
            'account and fill in the forms. The parent or guardian gives '
            'consent and uses the rights above on the child\'s behalf. The '
            'form records who filled it in.',
      ]),
      LegalSection('Cookies and your device', [
        'The apps use no advertising or analytics cookies. They store on '
            'your device only what they need: your sign-in session, and '
            'conveniences such as the last clinic you opened, the email you '
            'last signed in with, and your display settings. The security '
            'check on sign-in may set its own cookie to tell people from '
            'bots.',
        'Signing out ends the session on that device, and Settings can reset '
            'the display settings.',
      ]),
      LegalSection('Changes to this policy', [
        'If we change this policy, we will show you the new version in the '
            'app and, where the change matters, ask you to acknowledge it. '
            'The date at the top says which version this is.',
      ]),
      LegalSection('Contact us', [
        '$_op\nData Protection Officer: $_email',
      ]),
    ],
  );
}
