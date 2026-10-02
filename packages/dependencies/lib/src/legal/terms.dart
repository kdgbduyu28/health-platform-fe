import 'legal_document.dart';

/// The platform's Terms and Conditions, agreed to on the create-account form
/// and readable in Settings. Bump [version] whenever the wording changes
/// what someone agreed to.
abstract final class TermsAndConditions {
  static const version = '2026-09-30';

  static const _op = LegalContact.operator;
  static const _email = LegalContact.email;

  static const document = LegalDocument(
    id: 'terms',
    title: 'Terms and Conditions',
    version: version,
    intro: 'These Terms and Conditions govern your use of this clinic '
        'platform — the Patient, Doctor, Assistant and Admin apps — operated '
        'by $_op ("we", "us"). By creating an account or using the apps, you '
        'agree to them. If you do not agree, please do not use the apps.',
    sections: [
      LegalSection('The service', [
        'The apps help clinics and their patients manage appointments, '
            'patient information, dental charts, bills and reminders. The '
            'platform is a tool: care is given by the clinics and their '
            'licensed professionals, not by the platform.',
        'Nothing in the apps is medical advice. The apps are not for '
            'emergencies — in an emergency, call 911 or go to the nearest '
            'hospital.',
      ]),
      LegalSection('Your account', [
        '- Give true and complete information, and keep it up to date.',
        '- Keep your password to yourself. You are responsible for what is '
            'done with your account, so tell us at once at $_email if you '
            'think someone else has used it.',
        '- One account per person. Do not create an account for someone else '
            'unless you are their parent, guardian or otherwise legally '
            'allowed to act for them.',
        '- A patient under 18 should have a parent or guardian create the '
            'account and use it with them.',
        '- An account by itself gives access to nothing. You join a clinic '
            'with its join code; staff get access only when the clinic '
            'approves them.',
      ]),
      LegalSection('For patients', [
        '- A booking is a request until the clinic confirms it. The clinic may '
            'need to reschedule or cancel; you may reschedule or cancel as its '
            'rules allow. A visit you miss without notice may be recorded as '
            'a no-show.',
        '- Answer the patient information form truthfully and completely. '
            'Your care may depend on it — especially your medicines, '
            'allergies and conditions.',
        '- Prices, fees and bills are set by the clinic. You pay the clinic '
            'directly; the apps only record the payment. A statement printed '
            'from the apps is not an official receipt — ask the clinic for '
            'its official receipt.',
        '- Questions or disputes about your treatment or your bills are '
            'between you and the clinic.',
        '- Reminders and notifications can arrive late or not at all. Keep '
            'track of your own appointments too.',
      ]),
      LegalSection('For clinics and their staff', [
        'A clinic that uses the platform is responsible for:',
        '- the care it gives, and the accuracy of its records, prices and '
            'bills;',
        '- its patients\' records as their personal information controller '
            'under the Data Privacy Act, including giving patients notice, '
            'getting their consent, and meeting the rules on keeping medical '
            'records;',
        '- giving access only to its own authorised staff, at the right '
            'role, and removing it as soon as they leave;',
        '- having the right to any records it imports, and checking them; '
            'and',
        '- signing a written agreement with us for the processing we do on '
            'its behalf, as the law requires.',
        'Staff using the apps must:',
        '- use patient information only for their work at that clinic, and '
            'keep it confidential — clinical notes above all;',
        '- never share their account, password, staff code or tablet PIN;',
        '- unlock a tablet handed to a patient only with their own PIN, and '
            'take it back as soon as the patient is done;',
        '- keep exported files and printed statements safe, and delete or '
            'shred them when they are no longer needed; and',
        '- report any suspected leak or misuse of patient information to '
            'their clinic administrator and to us at $_email straight away.',
      ]),
      LegalSection('What you must not do', [
        '- look at, or try to get to, information you are not allowed to '
            'see;',
        '- get around the security check, sign-in or access rules, or use '
            'someone else\'s account;',
        '- probe, scan or test the security of the platform without our '
            'written permission;',
        '- use bots or scripts to collect information from the apps, or '
            'overload them;',
        '- upload anything harmful, or pretend to be someone else;',
        '- copy, sell or share patient information for any purpose other '
            'than the patient\'s care at the clinic; or',
        '- use the apps for anything unlawful.',
      ]),
      LegalSection('Privacy', [
        'How we handle personal information is set out in our Privacy '
            'Policy, which forms part of these Terms. Each clinic asks '
            'separately for your consent to collect your health information, '
            'on its patient information form.',
      ]),
      LegalSection('Fees', [
        'Patients are not charged for using the apps. Anything a clinic pays '
            'to use the platform is agreed with that clinic separately.',
      ]),
      LegalSection('Availability and changes to the service', [
        'We work to keep the apps available, but they may be unavailable at '
            'times — for maintenance, because of a provider\'s outage, or for '
            'reasons outside our control. We may add, change or remove '
            'features. Clinics should keep their own copies of the records '
            'they need, which the Admin and Assistant apps can export.',
      ]),
      LegalSection('Ownership', [
        'The apps, their design and their code belong to us or our '
            'licensors. Each clinic keeps its own name, logo and records, and '
            'you keep your personal information. We give you a personal, '
            'non-transferable right to use the apps under these Terms.',
      ]),
      LegalSection('Limits of our responsibility', [
        'The apps are provided "as is" and "as available". As far as the law '
            'allows, we are not responsible for the care, advice, decisions, '
            'prices or bills of any clinic, or for indirect or consequential '
            'losses, such as lost income or opportunities.',
        'Nothing in these Terms takes away rights you have under Philippine '
            'law that cannot be waived, including under the Data Privacy Act '
            'and the Consumer Act, or limits responsibility for fraud or gross '
            'negligence.',
      ]),
      LegalSection('Suspending or closing an account', [
        'You may ask us to close your account at any time at $_email. We or '
            'a clinic may suspend or remove access for a breach of these '
            'Terms, to protect patients or the platform, or when the law '
            'requires it; a clinic can remove access to that clinic only. '
            'After an account is closed, records are kept or deleted as the '
            'Privacy Policy says.',
      ]),
      LegalSection('Changes to these Terms', [
        'We may update these Terms. We will show you the new version in the '
            'app and, where the change matters, ask you to agree to it before '
            'you carry on. The date at the top says which version this is.',
      ]),
      LegalSection('Governing law', [
        'These Terms are governed by the laws of the Republic of the '
            'Philippines. If something goes wrong, contact us first and we '
            'will try to put it right. Any dispute we cannot settle together '
            'goes to the proper courts of the Philippines.',
      ]),
      LegalSection('Contact us', [
        '$_op\n$_email',
      ]),
    ],
  );
}
