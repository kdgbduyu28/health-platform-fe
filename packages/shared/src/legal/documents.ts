// The platform's Privacy Policy (Data Privacy Act of 2012, RA 10173) and
// Terms and Conditions, word for word as the Flutter apps showed them.
//
// They describe what the system actually does — keep them in step when a
// feature changes what is collected, who sees it or where it goes, and bump
// the version. Each account's acknowledgement records it
// (health-platform-be, policy_acknowledgements). Each clinic's consent to
// health information is separate: the patient information form asks for it.

import { LegalContact, type LegalDocument } from './legal_content';

const op = LegalContact.operator;
const email = LegalContact.email;

export const privacyPolicyVersion = "2026-09-30";
export const termsVersion = "2026-09-30";

export const privacyPolicy: LegalDocument = {
  id: "privacy",
  title: "Privacy Policy",
  version: privacyPolicyVersion,
  intro: `This Privacy Policy explains how personal information is handled in this clinic platform — the Patient, Doctor, Assistant and Admin apps — under the Data Privacy Act of 2012 (Republic Act No. 10173), its Implementing Rules and Regulations, and the rules of the National Privacy Commission (NPC).`,
  sections: [
    {
      heading: `Who we are`,
      body: [
        `The platform is operated by ${op} ("we", "us"). You can reach us, and our Data Protection Officer, at ${email}.`,
        `We have two roles. For your account — your name, email, password and sign-in records — we are the personal information controller. For your records at a clinic — your visits, medical history, dental chart and bills — that clinic is the personal information controller, and we process those records on its behalf.`,
        `Each clinic decides what it asks of its patients and is responsible for the care it gives. Questions about your records at a clinic can go to that clinic or to us; we will pass them on.`,
      ],
    },
    {
      heading: `What we collect`,
      body: [
        `- Your account: full name, email address and password. The password is stored only in scrambled (hashed) form; no one, including us, can read it.`,
        `- The patient information form, when you join a clinic or visit its front desk: name, birthday, sex, address, occupation, mobile number, email, emergency contact, the medicines you take, allergies, medical conditions, and the name you sign with. When a parent or guardian fills it in: their name, relationship to you, phone and email.`,
        `- Your visits: bookings, dates and times, the doctor and service, check-in and completion, cancellations and no-shows, doctors' clinical notes, and notes written to you.`,
        `- Your dental chart, at dental clinics: the condition of each tooth, and the work planned and done.`,
        `- Billing: bills and their items, prices and discounts, and payments with how they were made (cash, GCash, BPI, BDO or QR Ph). The apps only record payments; they do not handle money or card details.`,
        `- Clinic staff: name, email, role and clinic; for doctors, their profile, schedule and time off; a tablet PIN, stored only in hashed form.`,
        `- Security and records of activity: sign-in times, IP address, and browser and device details in our providers' logs; the automated check that tells people from bots on sign-in; a log of who changed a clinic's records and when; and a log of data exports.`,
        `- Notifications and calendar: your in-app notifications and which kinds you have turned off; if you turn on push notifications, your browser's push address; if you subscribe to your visits in a calendar app, a private link.`,
        `Health information, and details such as your age and sex, are sensitive personal information under the law, and we treat them with the extra care the law requires. Clinics may also bring in records they already hold on paper or in spreadsheets.`,
      ],
    },
    {
      heading: `How we use it, and why we may`,
      body: [
        `- To create and run your account and let you join clinics, because you asked us to (RA 10173, Sec. 12(b)).`,
        `- To book, confirm, remind you of, reschedule and record your visits, keep your chart and bill you: for your medical care by the clinic (Sec. 13(f)) and with the consent you give on its patient information form (Sec. 13(a)).`,
        `- To send you reminders and notifications, unless you turn them off.`,
        `- To keep the platform and your records secure — stopping misuse, protecting accounts, and keeping a record of changes — which the law requires of us (Sec. 20) and which is in everyone's legitimate interest (Sec. 12(f)).`,
        `- To meet legal duties, lawful orders, and the clinics' duties to keep medical and billing records (Sec. 12(c)).`,
        `We do not sell your information, use it for advertising, or build marketing profiles. No decision about you is made by automated means alone. We will not use your information for any new purpose without telling you first and, where the law requires, asking for your consent.`,
      ],
    },
    {
      heading: `Who can see it`,
      body: [
        `- You: your account, your information form, your visits and notes written to you, your dental chart, and your bills.`,
        `- Front desk staff: the clinic's patient list, information forms (including the medical answers, so they can prepare your visit), bookings and bills — but not doctors' clinical notes.`,
        `- Doctors: their clinic's patients, forms, visits, dental charts and clinical notes.`,
        `- Clinic administrators: everything at their clinic, including clinical notes, the ledger and the record of changes. A branch administrator sees only their branch.`,
        `- Other clinics: never your records at a clinic. If you are a patient at more than one clinic on the platform, your basic details (name, birthday, sex, contact details, address, occupation and emergency contact) are kept once and shared between the clinics you have joined, so a correction at one reaches the others. Your visits, forms, notes, charts and bills stay separate at each clinic.`,
        `- Us: only to run, support and secure the platform, or when the law requires it.`,
        `These limits are enforced by the database itself, not only by the apps.`,
      ],
    },
    {
      heading: `Service providers, and where your information is kept`,
      body: [
        `We use a small number of providers to run the platform. Each handles your information only to provide its service to us, and is bound to protect it.`,
        `- Supabase: our database and sign-in service. Your information is stored in its data centre in Mumbai, India.`,
        `- Cloudflare: hosts the apps and runs the security check on sign-in, sign-up and password reset.`,
        `- Our email provider: sends account emails, such as password reset codes.`,
        `- Your browser's push service (for example Google, Mozilla, Apple or Microsoft), only if you turn on push notifications, to deliver them.`,
        `- Google Calendar or your own calendar app, only if you add a visit to it or subscribe to your visits. To protect your privacy, calendar entries leave out the service you are seeing the doctor for.`,
        `Because your information is stored outside the Philippines, we remain responsible for it wherever it is kept (Sec. 21), and choose providers that protect it to the standard the law requires. We may disclose information when the law or a lawful order requires it.`,
      ],
    },
    {
      heading: `How long we keep it`,
      body: [
        `- Your account: until you ask us to close it.`,
        `- Medical, dental and billing records: kept by the clinic for as long as the rules on medical and tax records require, even after your account is closed; then deleted or anonymised.`,
        `- In-app notifications: deleted automatically after 90 days.`,
        `- The record of changes to clinic records: kept as long as the records it describes.`,
        `- Records of your agreement to this policy and the Terms: as long as your account.`,
      ],
    },
    {
      heading: `How we protect it`,
      body: [
        `- Your information is encrypted in transit and when stored.`,
        `- Every record is tied to its clinic, and the database decides who may read or change it by their role there.`,
        `- Clinical notes are for doctors and administrators only.`,
        `- Passwords and tablet PINs are stored only in hashed form; repeated wrong PINs lock the tablet.`,
        `- An automated check stands in the way of bots trying to guess passwords.`,
        `- Changes to patient and clinic records are logged with who made them and when, and data exports are logged.`,
        `- A tablet handed to a patient shows only the information form until a staff member unlocks it with their PIN.`,
        `If a breach puts your information at real risk, we and the clinic will notify the National Privacy Commission and you within 72 hours of knowing about it, as the NPC requires.`,
      ],
    },
    {
      heading: `Your rights`,
      body: [
        `Under the Data Privacy Act you have the right to:`,
        `- be informed of how your information is collected and used;`,
        `- see your information and get a copy of it;`,
        `- have wrong or incomplete information corrected;`,
        `- object to its use, or withdraw your consent;`,
        `- have it blocked, removed or destroyed where the law allows;`,
        `- receive it in a commonly used electronic format, to take to someone else;`,
        `- be compensated for damage caused by its misuse; and`,
        `- complain to the National Privacy Commission.`,
        `To use any of these, email ${email} or ask your clinic. We may need to confirm who you are first. Some things you can change yourself in the app.`,
        `If you withdraw your consent, a clinic may still keep the records it must keep by law, and may not be able to treat you safely without the information it needs.`,
        `You can complain to the National Privacy Commission at privacy.gov.ph.`,
      ],
    },
    {
      heading: `Children`,
      body: [
        `A patient under 18 should have a parent or guardian create the account and fill in the forms. The parent or guardian gives consent and uses the rights above on the child's behalf. The form records who filled it in.`,
      ],
    },
    {
      heading: `Cookies and your device`,
      body: [
        `The apps use no advertising or analytics cookies. They store on your device only what they need: your sign-in session, and conveniences such as the last clinic you opened, the email you last signed in with, and your display settings. The security check on sign-in may set its own cookie to tell people from bots.`,
        `Signing out ends the session on that device, and Settings can reset the display settings.`,
      ],
    },
    {
      heading: `Changes to this policy`,
      body: [
        `If we change this policy, we will show you the new version in the app and, where the change matters, ask you to acknowledge it. The date at the top says which version this is.`,
      ],
    },
    {
      heading: `Contact us`,
      body: [
        `${op}
Data Protection Officer: ${email}`,
      ],
    },
  ],
};

export const termsAndConditions: LegalDocument = {
  id: "terms",
  title: "Terms and Conditions",
  version: termsVersion,
  intro: `These Terms and Conditions govern your use of this clinic platform — the Patient, Doctor, Assistant and Admin apps — operated by ${op} ("we", "us"). By creating an account or using the apps, you agree to them. If you do not agree, please do not use the apps.`,
  sections: [
    {
      heading: `The service`,
      body: [
        `The apps help clinics and their patients manage appointments, patient information, dental charts, bills and reminders. The platform is a tool: care is given by the clinics and their licensed professionals, not by the platform.`,
        `Nothing in the apps is medical advice. The apps are not for emergencies — in an emergency, call 911 or go to the nearest hospital.`,
      ],
    },
    {
      heading: `Your account`,
      body: [
        `- Give true and complete information, and keep it up to date.`,
        `- Keep your password to yourself. You are responsible for what is done with your account, so tell us at once at ${email} if you think someone else has used it.`,
        `- One account per person. Do not create an account for someone else unless you are their parent, guardian or otherwise legally allowed to act for them.`,
        `- A patient under 18 should have a parent or guardian create the account and use it with them.`,
        `- An account by itself gives access to nothing. You join a clinic with its join code; staff get access only when the clinic approves them.`,
      ],
    },
    {
      heading: `For patients`,
      body: [
        `- A booking is a request until the clinic confirms it. The clinic may need to reschedule or cancel; you may reschedule or cancel as its rules allow. A visit you miss without notice may be recorded as a no-show.`,
        `- Answer the patient information form truthfully and completely. Your care may depend on it — especially your medicines, allergies and conditions.`,
        `- Prices, fees and bills are set by the clinic. You pay the clinic directly; the apps only record the payment. A statement printed from the apps is not an official receipt — ask the clinic for its official receipt.`,
        `- Questions or disputes about your treatment or your bills are between you and the clinic.`,
        `- Reminders and notifications can arrive late or not at all. Keep track of your own appointments too.`,
      ],
    },
    {
      heading: `For clinics and their staff`,
      body: [
        `A clinic that uses the platform is responsible for:`,
        `- the care it gives, and the accuracy of its records, prices and bills;`,
        `- its patients' records as their personal information controller under the Data Privacy Act, including giving patients notice, getting their consent, and meeting the rules on keeping medical records;`,
        `- giving access only to its own authorised staff, at the right role, and removing it as soon as they leave;`,
        `- having the right to any records it imports, and checking them; and`,
        `- signing a written agreement with us for the processing we do on its behalf, as the law requires.`,
        `Staff using the apps must:`,
        `- use patient information only for their work at that clinic, and keep it confidential — clinical notes above all;`,
        `- never share their account, password, staff code or tablet PIN;`,
        `- unlock a tablet handed to a patient only with their own PIN, and take it back as soon as the patient is done;`,
        `- keep exported files and printed statements safe, and delete or shred them when they are no longer needed; and`,
        `- report any suspected leak or misuse of patient information to their clinic administrator and to us at ${email} straight away.`,
      ],
    },
    {
      heading: `What you must not do`,
      body: [
        `- look at, or try to get to, information you are not allowed to see;`,
        `- get around the security check, sign-in or access rules, or use someone else's account;`,
        `- probe, scan or test the security of the platform without our written permission;`,
        `- use bots or scripts to collect information from the apps, or overload them;`,
        `- upload anything harmful, or pretend to be someone else;`,
        `- copy, sell or share patient information for any purpose other than the patient's care at the clinic; or`,
        `- use the apps for anything unlawful.`,
      ],
    },
    {
      heading: `Privacy`,
      body: [
        `How we handle personal information is set out in our Privacy Policy, which forms part of these Terms. Each clinic asks separately for your consent to collect your health information, on its patient information form.`,
      ],
    },
    {
      heading: `Fees`,
      body: [
        `Patients are not charged for using the apps. Anything a clinic pays to use the platform is agreed with that clinic separately.`,
      ],
    },
    {
      heading: `Availability and changes to the service`,
      body: [
        `We work to keep the apps available, but they may be unavailable at times — for maintenance, because of a provider's outage, or for reasons outside our control. We may add, change or remove features. Clinics should keep their own copies of the records they need, which the Admin and Assistant apps can export.`,
      ],
    },
    {
      heading: `Ownership`,
      body: [
        `The apps, their design and their code belong to us or our licensors. Each clinic keeps its own name, logo and records, and you keep your personal information. We give you a personal, non-transferable right to use the apps under these Terms.`,
      ],
    },
    {
      heading: `Limits of our responsibility`,
      body: [
        `The apps are provided "as is" and "as available". As far as the law allows, we are not responsible for the care, advice, decisions, prices or bills of any clinic, or for indirect or consequential losses, such as lost income or opportunities.`,
        `Nothing in these Terms takes away rights you have under Philippine law that cannot be waived, including under the Data Privacy Act and the Consumer Act, or limits responsibility for fraud or gross negligence.`,
      ],
    },
    {
      heading: `Suspending or closing an account`,
      body: [
        `You may ask us to close your account at any time at ${email}. We or a clinic may suspend or remove access for a breach of these Terms, to protect patients or the platform, or when the law requires it; a clinic can remove access to that clinic only. After an account is closed, records are kept or deleted as the Privacy Policy says.`,
      ],
    },
    {
      heading: `Changes to these Terms`,
      body: [
        `We may update these Terms. We will show you the new version in the app and, where the change matters, ask you to agree to it before you carry on. The date at the top says which version this is.`,
      ],
    },
    {
      heading: `Governing law`,
      body: [
        `These Terms are governed by the laws of the Republic of the Philippines. If something goes wrong, contact us first and we will try to put it right. Any dispute we cannot settle together goes to the proper courts of the Philippines.`,
      ],
    },
    {
      heading: `Contact us`,
      body: [
        `${op}
${email}`,
      ],
    },
  ],
};
