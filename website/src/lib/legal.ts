import { CONTACT_ADDRESS, CONTACT_COMPANY, CONTACT_EMAIL } from './site-links';

/**
 * The approved legal and policy documents.
 *
 * The text lives here as data rather than as JSX inside each page so that a
 * wording change is a one-line edit instead of a hunt through five 400-line
 * components, and so the pages themselves stay trivial.
 *
 * Wording note: the approved documents (Terms & Conditions, Privacy Policy,
 * Cancellation, Rescheduling & Refund Policy, Salon Partner Policy — Nov 2026)
 * name a 90-minute cancellation/reschedule cutoff and a 15-minute QR reveal.
 * Those figures are SuperAdmin Policy Settings (`cancellation_cutoff_minutes`,
 * `reschedule_cutoff_minutes`, `appointment_start_early_minutes`). If a
 * setting is changed, the wording here must change with it.
 */

export interface LegalBlock {
  /** A bolded sub-clause label, e.g. "C.1 Personal Information". */
  lead?: string;
  /** Rendered as a bullet list. Omit for a plain paragraph. */
  bullets?: string[];
  text?: string;
}

export interface LegalSection {
  heading: string;
  blocks: LegalBlock[];
}

export interface RelatedLink {
  href: string;
  label: string;
}

export interface LegalDocument {
  slug: string;
  title: string;
  kicker: string;
  /** The `description` for the page metadata, and the standfirst under the title. */
  summary: string;
  sections: LegalSection[];
  /** Cross-references to the other documents, shown as a small nav under the text. */
  related?: RelatedLink[];
}

// ---------------------------------------------------------------- shared bits

const ALL_RELATED: RelatedLink[] = [
  { href: '/about', label: 'About BookALook' },
  { href: '/terms', label: 'Terms & Conditions' },
  { href: '/privacy', label: 'Privacy Policy' },
  { href: '/cancellation-refund', label: 'Cancellation, Rescheduling & Refund Policy' },
  { href: '/partner-terms', label: 'Salon Partner Policy' },
];

// Reads as a letterhead: who you are writing to, where they are, how to reach
// them. The "contact us at:" line that precedes this list in the Terms and
// Privacy documents needs the name before the address, not after it.
const CONTACT_BLOCKS: LegalBlock[] = [
  { text: CONTACT_COMPANY },
  { text: CONTACT_ADDRESS },
  { text: CONTACT_EMAIL },
];

// ------------------------------------------------------- terms & conditions

export const TERMS_OF_USE: LegalDocument = {
  slug: 'terms',
  title: 'Terms & Conditions',
  kicker: 'Book A Look',
  summary:
    'These Terms & Conditions govern access to and use of the Book A Look website, mobile application and related services operated by Bookalook Private Limited.',
  related: ALL_RELATED,
  sections: [
    {
      heading: '1. Introduction',
      blocks: [
        {
          text: 'These Terms & Conditions govern access to and use of the Book A Look website, mobile application, and related services operated by Bookalook Private Limited ("Book A Look", "Company", "we", "us" or "our").',
        },
        {
          text: 'By accessing the website, downloading or using the application, creating an account, or making a booking, you ("Customer", "User" or "you") agree to these Terms & Conditions.',
        },
        { text: 'If you do not agree with these terms, please discontinue using our services.' },
      ],
    },
    {
      heading: '2. About Book A Look',
      blocks: [
        {
          text: 'Book A Look is an online salon discovery and appointment booking marketplace that enables customers to discover participating salons, view available services and listed prices, check appointment availability, and book appointments.',
        },
        { text: 'Book A Look acts as a technology platform connecting customers with independent salon partners.' },
        { text: 'Unless expressly stated otherwise, the salon partner is responsible for:' },
        {
          bullets: [
            'Providing the salon services.',
            'Maintaining service quality and hygiene.',
            'Ensuring staff availability.',
            'Delivering services at the listed prices.',
            'Handling customer concerns relating to the actual salon service.',
          ],
        },
        { text: 'Book A Look does not itself provide salon, grooming, or beauty services.' },
      ],
    },
    {
      heading: '3. Eligibility and Account Registration',
      blocks: [
        { text: 'Users must provide accurate and complete information when creating an account or making a booking.' },
        { text: 'You agree:' },
        {
          bullets: [
            'To provide a valid mobile number and other requested information.',
            'Not to impersonate another person.',
            'Not to create fraudulent or duplicate accounts.',
            'To maintain the confidentiality of your account credentials and OTPs.',
            'To notify us if you suspect unauthorized access to your account.',
          ],
        },
        { text: 'You are responsible for activities performed through your account, subject to applicable law.' },
      ],
    },
    {
      heading: '4. Salon Information and Services',
      blocks: [
        {
          text: 'Salon profiles, service descriptions, prices, photographs, operating hours, and availability may be provided by salon partners.',
        },
        {
          text: 'Book A Look makes reasonable efforts to maintain accurate platform information but cannot guarantee that every listing is continuously updated or error-free.',
        },
        { text: 'Customers should review the service details and applicable price before confirming a booking.' },
      ],
    },
    {
      heading: '5. Appointment Booking',
      blocks: [
        { text: 'A booking request must be submitted through the available booking interface.' },
        {
          text: 'A booking shall be treated as confirmed only when the platform displays a confirmed booking status or communicates confirmation through an authorized notification channel.',
        },
        { text: 'Each confirmed booking may have a unique booking reference and QR code.' },
        { text: 'The customer must verify:' },
        {
          bullets: [
            'Salon name and location.',
            'Selected service.',
            'Appointment date and time.',
            'Applicable service price.',
            'Selected payment method.',
          ],
        },
        { text: 'The customer should arrive at the salon at the scheduled appointment time.' },
      ],
    },
    {
      heading: '6. Payment Methods',
      blocks: [
        {
          text: 'Book A Look may support the following payment methods, depending on the salon, service, and availability:',
        },
        { lead: 'A. Online Payment' },
        { text: 'Customers may pay through supported payment gateways and payment methods displayed at checkout.' },
        {
          text: 'Online transactions are subject to the applicable payment gateway terms, bank policies, and transaction processing rules.',
        },
        {
          text: 'A booking requiring online payment will be confirmed according to the payment and booking confirmation process displayed in the application.',
        },
        { lead: 'B. Pay at Store' },
        { text: 'Customers selecting Pay at Store must pay the salon directly when visiting the salon.' },
        {
          text: 'Accepted payment methods at the salon may include cash, UPI, debit card, credit card, or other methods accepted by that salon.',
        },
        { text: 'Book A Look does not collect the service amount for a Pay at Store booking.' },
        { text: 'Customers should confirm any payment-related questions directly with the salon.' },
      ],
    },
    {
      heading: '7. Pricing and Additional Charges',
      blocks: [
        { text: 'The prices displayed on Book A Look are based on information supplied by the salon partner.' },
        { text: 'Customers must review the displayed service price before booking.' },
        {
          text: 'Any additional service, upgrade, or charge must be communicated to the customer before the customer agrees to receive it.',
        },
        { text: 'Book A Look does not authorize salons to impose undisclosed charges.' },
      ],
    },
    {
      heading: '8. Cancellation and Rescheduling',
      blocks: [
        {
          text: 'Customers may cancel or request rescheduling through the available booking functionality, subject to the following standard rule:',
        },
        {
          bullets: [
            'Cancellation or rescheduling must be completed at least 90 minutes before the scheduled appointment start time.',
            'Requests made within the 90-minute restricted period may not be permitted through the platform.',
            'Rescheduling is subject to available appointment slots.',
            'A rescheduled appointment will be governed by the revised booking details and applicable cancellation rules.',
          ],
        },
        { text: 'Any exception must be handled through the customer support process and in accordance with applicable law.' },
        { text: 'Detailed refund conditions are described in the Cancellation, Rescheduling and Refund Policy.' },
      ],
    },
    {
      heading: '9. QR Code and Salon Check-in',
      blocks: [
        { text: 'A unique QR code may be generated for each confirmed booking.' },
        { text: 'Where the QR check-in feature is enabled:' },
        {
          bullets: [
            "The QR code becomes visible in the customer's booking section 15 minutes before the scheduled appointment.",
            'The QR code is intended to verify the booking at the salon.',
            'The salon may scan the QR code using the authorized check-in functionality.',
            "A QR code must not be shared, copied, misused, or presented for another person's booking.",
            "QR validation and booking status are subject to the platform's server-side verification.",
          ],
        },
        { text: 'A QR code does not independently guarantee that a salon service has been completed.' },
      ],
    },
    {
      heading: '10. Customer Responsibilities',
      blocks: [
        { text: 'Customers must:' },
        {
          bullets: [
            'Provide accurate booking information.',
            'Arrive at the salon on time.',
            'Follow salon hygiene and safety instructions.',
            'Treat salon staff respectfully.',
            'Avoid fraudulent bookings and misuse of promotional offers.',
            'Inform the salon of any relevant service requirements before the appointment.',
          ],
        },
      ],
    },
    {
      heading: '11. Salon Partner Responsibilities',
      blocks: [
        {
          text: 'Salon partners are responsible for delivering the booked services professionally and in accordance with applicable laws.',
        },
        {
          text: 'Salon partners must maintain accurate service prices, operating hours, and availability and must not knowingly accept bookings they cannot fulfil.',
        },
      ],
    },
    {
      heading: '12. Offers and Promotions',
      blocks: [
        {
          text: 'Promotional offers may be subject to additional eligibility conditions, expiry dates, service restrictions, and participating salon limitations.',
        },
        { text: 'Offers cannot be exchanged for cash unless expressly stated.' },
        {
          text: 'Book A Look may withdraw or modify an offer in accordance with its stated conditions and applicable law.',
        },
      ],
    },
    {
      heading: '13. Reviews and User Content',
      blocks: [
        { text: 'Customers must provide genuine and honest reviews based on their actual experience.' },
        {
          text: 'We may moderate, remove, or restrict content that is unlawful, abusive, misleading, fraudulent, or violates these terms.',
        },
      ],
    },
    {
      heading: '14. Platform Availability',
      blocks: [
        {
          text: 'We may update, maintain, suspend, or modify any part of the website or application to improve functionality, security, or performance.',
        },
        { text: 'We will make reasonable efforts to minimize service disruption.' },
      ],
    },
    {
      heading: '15. Limitation of Liability',
      blocks: [
        {
          text: 'To the extent permitted by applicable law, Book A Look shall not be responsible for independent salon operations, service delivery decisions, or conduct of salon personnel.',
        },
        {
          text: 'Nothing in these terms excludes liability that cannot legally be excluded, including liability arising from fraud, wilful misconduct, or other non-excludable obligations.',
        },
      ],
    },
    {
      heading: '16. Suspension and Termination',
      blocks: [
        {
          text: 'Book A Look may restrict or suspend an account where there is reasonable evidence of fraud, misuse, unlawful activity, security threats, or repeated violations of these terms.',
        },
        {
          text: 'Users may request account closure through customer support, subject to outstanding bookings, transactions, and applicable legal retention requirements.',
        },
      ],
    },
    {
      heading: '17. Privacy',
      blocks: [{ text: 'Personal information is handled in accordance with the Book A Look Privacy Policy.' }],
    },
    {
      heading: '18. Grievance Redressal',
      blocks: [
        { text: 'For complaints, concerns, or disputes, contact:' },
        { lead: 'Grievance Officer / Customer Support' },
        ...CONTACT_BLOCKS,
        { text: 'Please include your booking reference where relevant.' },
      ],
    },
    {
      heading: '19. Governing Law and Jurisdiction',
      blocks: [
        { text: 'These terms shall be governed by the laws of India.' },
        {
          text: "Subject to applicable consumer protection laws and the jurisdiction of competent authorities, courts having jurisdiction at the Company's registered office location shall have jurisdiction over disputes.",
        },
      ],
    },
    {
      heading: '20. Changes to These Terms',
      blocks: [
        {
          text: 'Book A Look may update these terms from time to time. The revised version will be published on the website and/or application with an updated effective date.',
        },
        {
          text: 'Continued use of the platform after the effective date will be subject to the revised terms, to the extent permitted by law.',
        },
      ],
    },
  ],
};

// ------------------------------------------------------------ privacy policy

export const PRIVACY_POLICY: LegalDocument = {
  slug: 'privacy',
  title: 'Privacy Policy',
  kicker: 'Book A Look',
  summary:
    'What information Book A Look collects through its website and mobile application, how it is used and shared, and the choices available to you.',
  related: ALL_RELATED,
  sections: [
    {
      heading: '1. Introduction',
      blocks: [
        {
          text: 'Bookalook Private Limited ("Book A Look", "Company", "we", "us" or "our") respects your privacy and is committed to protecting personal information collected through our website, mobile application, and related services.',
        },
        {
          text: 'This Privacy Policy explains what information we collect, how we use it, when it may be shared, and the choices available to users.',
        },
        { text: 'By accessing or using Book A Look, you acknowledge that you have read this Privacy Policy.' },
      ],
    },
    {
      heading: '2. Information We Collect',
      blocks: [
        { text: 'Depending on how you use our platform, we may collect:' },
        { lead: 'A. Personal Information' },
        { bullets: ['Name.', 'Mobile number.', 'Email address.', 'Account and profile details.'] },
        { lead: 'B. Booking Information' },
        {
          bullets: [
            'Selected salon.',
            'Selected service.',
            'Appointment date and time.',
            'Booking reference.',
            'Booking and cancellation history.',
            'QR code and check-in status.',
          ],
        },
        { lead: 'C. Location Information' },
        {
          text: 'Where location permissions are enabled, we may process location information to help display nearby salons or improve location-based search.',
        },
        {
          text: 'You may disable location permissions through your device settings. Some location-related features may then become unavailable.',
        },
        { lead: 'D. Payment Information' },
        {
          text: 'For online payments, transactions are processed through authorized third-party payment service providers.',
        },
        { text: 'We may receive information such as:' },
        {
          bullets: [
            'Transaction reference.',
            'Payment status.',
            'Payment method category.',
            'Refund status.',
            'Relevant transaction records.',
          ],
        },
        {
          text: 'We do not intend to store complete card numbers, CVV values, or payment authentication credentials on our servers.',
        },
        {
          text: 'For Pay at Store bookings, we may record the selected payment method or booking payment status where supported. Payment is made directly to the salon.',
        },
        { lead: 'E. Technical Information' },
        {
          bullets: [
            'Device and operating system information.',
            'App version.',
            'IP address and basic log information.',
            'Crash reports and diagnostic information.',
            'Usage and interaction information.',
          ],
        },
      ],
    },
    {
      heading: '3. How We Use Your Information',
      blocks: [
        { text: 'We may use your information to:' },
        {
          bullets: [
            'Create and manage customer accounts.',
            'Authenticate users through OTP or other supported methods.',
            'Display salons and services.',
            'Create and manage appointments.',
            'Generate booking references and QR codes.',
            'Send booking confirmations and reminders.',
            'Process online payments and refunds through payment partners.',
            'Share relevant booking information with the selected salon.',
            'Provide customer support.',
            'Detect fraud and unauthorized activities.',
            'Improve application performance and user experience.',
            'Meet legal, regulatory, accounting, and security requirements.',
          ],
        },
      ],
    },
    {
      heading: '4. Sharing Information With Salon Partners',
      blocks: [
        {
          text: 'When you make a booking, relevant information may be shared with the selected salon so that it can manage and fulfil your appointment.',
        },
        { text: 'This may include:' },
        {
          bullets: [
            'Customer name.',
            'Contact information necessary for appointment coordination.',
            'Selected service.',
            'Appointment date and time.',
            'Booking reference.',
            'Relevant booking status.',
          ],
        },
        {
          text: 'Salon partners are expected to use this information only for legitimate booking-related purposes and their applicable legal obligations.',
        },
      ],
    },
    {
      heading: '5. Sharing Information With Third Parties',
      blocks: [
        { text: 'We may share necessary information with:' },
        {
          bullets: [
            'Payment gateway providers.',
            'OTP and authentication service providers.',
            'WhatsApp or other notification providers.',
            'Cloud hosting and infrastructure providers.',
            'Analytics and crash-monitoring providers.',
            'Customer support and operational service providers.',
            'Government authorities or law enforcement where legally required.',
          ],
        },
        {
          text: 'Such sharing will be limited to legitimate operational, contractual, security, or legal purposes.',
        },
      ],
    },
    {
      heading: '6. Online Payment Privacy',
      blocks: [
        {
          text: 'For online payments, the payment gateway processes payment credentials according to its own security and privacy practices.',
        },
        {
          text: 'Book A Look may receive transaction confirmation and related payment status information to update your booking.',
        },
        { text: 'Customers should review the privacy policy of the payment provider where applicable.' },
      ],
    },
    {
      heading: '7. Pay at Store Privacy',
      blocks: [
        { text: 'For Pay at Store bookings, Book A Look does not collect the service payment from the customer.' },
        { text: 'The salon may independently process the payment and maintain its own transaction records.' },
        { text: 'The salon is responsible for handling payment information collected directly by it.' },
      ],
    },
    {
      heading: '8. Notifications and Communications',
      blocks: [
        { text: 'We may send:' },
        {
          bullets: [
            'OTP and authentication messages.',
            'Booking confirmations.',
            'Appointment reminders.',
            'Cancellation and rescheduling updates.',
            'Payment and refund updates.',
            'Important service announcements.',
            'Promotional communications, where appropriate and subject to applicable consent requirements.',
          ],
        },
        {
          text: 'You may opt out of promotional communications through available controls. Transactional and essential service communications may still be sent where necessary.',
        },
      ],
    },
    {
      heading: '9. Data Retention',
      blocks: [
        {
          text: 'We retain personal information only for as long as reasonably necessary for the purposes described in this policy, including:',
        },
        {
          bullets: [
            'Maintaining accounts.',
            'Completing bookings.',
            'Handling disputes and refunds.',
            'Meeting accounting and legal requirements.',
            'Preventing fraud and ensuring platform security.',
          ],
        },
        { text: 'Information may be retained for longer where required by applicable law.' },
      ],
    },
    {
      heading: '10. Data Security',
      blocks: [
        {
          text: 'We implement reasonable technical and organizational safeguards to protect personal information against unauthorized access, disclosure, alteration, loss, and misuse.',
        },
        { text: 'However, no electronic transmission or storage method can be guaranteed to be completely secure.' },
      ],
    },
    {
      heading: '11. User Rights and Choices',
      blocks: [
        { text: 'Subject to applicable law, users may request:' },
        {
          bullets: [
            'Access to information relating to their account.',
            'Correction of inaccurate personal information.',
            'Deletion of personal information where legally permissible.',
            'Withdrawal of consent where processing is based on consent.',
            'Grievance redressal regarding personal information.',
          ],
        },
        { text: `Requests can be submitted to ${CONTACT_EMAIL}.` },
        { text: 'We may need to verify your identity before processing such requests.' },
      ],
    },
    {
      heading: "12. Children's Privacy",
      blocks: [
        { text: 'Our platform is intended for individuals legally capable of entering into applicable transactions.' },
        {
          text: 'If we become aware that personal information has been collected from a child in circumstances prohibited by applicable law, we will take appropriate steps.',
        },
      ],
    },
    {
      heading: '13. Cookies and Similar Technologies',
      blocks: [
        {
          text: 'Our website may use cookies and similar technologies for essential functionality, analytics, security, and user experience.',
        },
        {
          text: 'Users can manage browser cookie settings. Disabling certain cookies may affect website functionality.',
        },
      ],
    },
    {
      heading: '14. Third-Party Links',
      blocks: [
        { text: 'Our website or application may contain links to third-party websites or services.' },
        {
          text: 'We are not responsible for the privacy practices of external services. Users should review their respective privacy policies.',
        },
      ],
    },
    {
      heading: '15. Changes to This Privacy Policy',
      blocks: [
        { text: 'We may update this policy to reflect changes in our services, technology, or applicable laws.' },
        { text: 'The revised policy will be published with an updated date.' },
      ],
    },
    {
      heading: '16. Contact and Grievance Redressal',
      blocks: [{ lead: 'Privacy and Grievance Contact' }, ...CONTACT_BLOCKS],
    },
  ],
};

// ---------------------------------------- cancellation, rescheduling & refund

export const CANCELLATION_REFUND_POLICY: LegalDocument = {
  slug: 'cancellation-refund',
  title: 'Cancellation, Rescheduling & Refund Policy',
  kicker: 'Book A Look',
  summary:
    'How cancellation, rescheduling, refunds and appointment-related payment issues are handled for bookings made through Book A Look.',
  related: ALL_RELATED,
  sections: [
    {
      heading: '1. Introduction',
      blocks: [
        {
          text: 'This policy governs cancellation, rescheduling, refunds, and appointment-related payment issues for bookings made through Book A Look.',
        },
        { text: 'Book A Look is a marketplace connecting customers with independent salon partners.' },
      ],
    },
    {
      heading: '2. Cancellation Time Limit',
      blocks: [
        {
          text: 'Customers may cancel a confirmed appointment through the application, subject to the following standard rule:',
        },
        {
          bullets: [
            'Cancellation must be completed at least 90 minutes before the scheduled appointment start time.',
            'Cancellations requested within 90 minutes of the appointment may not be permitted through the application.',
            'Requests for exceptions may be submitted to customer support and will be reviewed based on the circumstances and applicable law.',
          ],
        },
        {
          text: 'The relevant appointment time displayed in the booking details will be used to determine the cancellation deadline.',
        },
      ],
    },
    {
      heading: '3. Rescheduling Rules',
      blocks: [
        { text: 'Customers may request rescheduling at least 90 minutes before the original appointment start time.' },
        { text: 'Rescheduling:' },
        {
          bullets: [
            'Is subject to available appointment slots.',
            'Must be completed through the supported application functionality or customer support process.',
            'Is not confirmed until the revised appointment details are displayed as confirmed.',
            'May be subject to additional restrictions displayed during the booking process.',
          ],
        },
        {
          text: 'Any restriction on repeated rescheduling must be clearly disclosed to the customer before the booking is confirmed.',
        },
      ],
    },
    {
      heading: '4. Online Payment Bookings',
      blocks: [
        { text: 'Where a customer has paid online:' },
        { lead: 'A. Cancellation Within the Permitted Time' },
        {
          text: 'Where cancellation is completed at least 90 minutes before the appointment, the customer will be eligible for a refund of the amount paid for the cancelled booking, subject to applicable law and any clearly disclosed non-refundable charges permitted by law.',
        },
        { lead: 'B. Cancellation Within the Restricted Period' },
        {
          text: 'Where cancellation is attempted within 90 minutes of the appointment, the platform may not permit cancellation or refund through the normal booking process.',
        },
        {
          text: 'Exceptions may be considered where the salon cancels, the service cannot be provided, a duplicate transaction occurs, or another circumstance warrants a remedy under applicable law.',
        },
        { lead: 'C. Salon-Initiated Cancellation' },
        {
          text: 'If a salon cancels a confirmed appointment and the service cannot be provided, the customer will be eligible for a refund of the amount paid online for that booking.',
        },
        { lead: 'D. Failed or Duplicate Transactions' },
        {
          text: 'If a customer is charged but the booking is not successfully confirmed, or a duplicate payment is identified, the transaction will be investigated and the applicable amount refunded or reversed.',
        },
      ],
    },
    {
      heading: '5. Pay at Store Bookings',
      blocks: [
        { text: 'For Pay at Store bookings:' },
        {
          bullets: [
            'The customer pays the salon directly.',
            'Book A Look does not collect the service amount.',
            'Book A Look cannot directly refund an amount that it has not received.',
            'If the salon has collected any advance payment independently, the salon is responsible for processing the applicable refund, subject to applicable law and the disclosed payment terms.',
          ],
        },
        { text: 'Customers may contact Book A Look for assistance in resolving booking-related disputes.' },
      ],
    },
    {
      heading: '6. Refund Processing',
      blocks: [
        { text: 'For eligible online payment refunds:' },
        {
          bullets: [
            'Refund requests will be initiated after the relevant cancellation or refund decision is confirmed.',
            'Refunds will ordinarily be sent to the original payment method.',
            'The payment gateway, bank, or payment provider may require additional processing time.',
            'The expected processing timeline should be displayed or communicated to the customer.',
          ],
        },
        { text: "The final crediting time may depend on the customer's bank or payment provider." },
      ],
    },
    {
      heading: '7. No-Show',
      blocks: [
        {
          text: 'If a customer fails to arrive for a confirmed appointment without cancelling it within the permitted time:',
        },
        {
          bullets: [
            'The booking may be marked as a no-show.',
            'The salon may decline to provide the missed appointment slot.',
            'Refund eligibility will be assessed according to the disclosed booking conditions and applicable law.',
          ],
        },
        { text: 'No-show conditions must be visible to the customer before confirmation.' },
      ],
    },
    {
      heading: '8. Service Not Provided or Unsatisfactory Service',
      blocks: [
        {
          text: 'If a salon fails to provide a confirmed service, customers should report the issue to Book A Look as soon as possible.',
        },
        {
          text: 'Where a service is materially different from what was booked, or a service is not provided, Book A Look may coordinate with the salon and assess an appropriate remedy.',
        },
        { text: 'Refunds or other remedies will be considered in accordance with applicable consumer protection law.' },
      ],
    },
    {
      heading: '9. How to Request Assistance',
      blocks: [
        { text: 'Customers should contact:' },
        { text: `Email: ${CONTACT_EMAIL}` },
        { text: 'Please provide:' },
        {
          bullets: [
            'Customer name.',
            'Booking reference.',
            'Salon name.',
            'Appointment date and time.',
            'Transaction reference, if applicable.',
            'Brief description of the issue.',
          ],
        },
      ],
    },
    {
      heading: '10. Policy Changes',
      blocks: [
        {
          text: 'Book A Look may revise this policy from time to time. Updated terms will be published on the website and application.',
        },
      ],
    },
  ],
};

// ---------------------------------------------------- salon partner policy

export const PARTNER_TERMS: LegalDocument = {
  slug: 'partner-terms',
  title: 'Salon Partner Policy',
  kicker: 'Book A Look for Salons',
  summary:
    'The rules for salons, barbershops, grooming studios and other service providers that list and take bookings on Book A Look.',
  related: ALL_RELATED,
  sections: [
    {
      heading: '1. Introduction',
      blocks: [
        {
          text: 'This Salon Partner Policy governs the participation of salons, barbershops, grooming studios, and other eligible service providers ("Salon Partners") on Book A Look, operated by Bookalook Private Limited.',
        },
        {
          text: 'By registering with or using the Book A Look partner platform, the Salon Partner agrees to comply with this policy and the applicable partner agreement.',
        },
      ],
    },
    {
      heading: '2. Platform Relationship',
      blocks: [
        {
          text: 'Book A Look provides technology that enables salon discovery, appointment booking, and booking management.',
        },
        {
          text: 'The Salon Partner remains an independent service provider and is responsible for delivering salon services to customers.',
        },
        {
          text: 'Nothing in this policy automatically creates an employer-employee, partnership, franchise, or agency relationship between Book A Look and a Salon Partner.',
        },
      ],
    },
    {
      heading: '3. Salon Registration',
      blocks: [
        { text: 'Salon Partners must provide accurate information, including:' },
        {
          bullets: [
            'Business and salon name.',
            'Owner or authorized representative details.',
            'Valid contact information.',
            'Salon address and location.',
            'Applicable business registration or licences, where required.',
            'Service categories and prices.',
            'Operating hours.',
            'Staff and appointment availability.',
          ],
        },
        { text: "Book A Look may request supporting documents to verify the salon's information." },
      ],
    },
    {
      heading: '4. Listing Accuracy',
      blocks: [
        { text: 'Salon Partners must:' },
        {
          bullets: [
            'Maintain accurate salon profiles.',
            'Provide genuine photographs and descriptions.',
            'Keep service prices updated.',
            'Update operating hours and holiday schedules.',
            'Maintain accurate appointment availability.',
            'Inform Book A Look about changes to business details.',
          ],
        },
        { text: 'Misleading listings, fake prices, or unauthorized use of images are prohibited.' },
      ],
    },
    {
      heading: '5. Appointment Management',
      blocks: [
        { text: 'Salon Partners must:' },
        {
          bullets: [
            'Monitor incoming bookings.',
            "Accept or reject booking requests according to the platform's booking workflow.",
            'Avoid accepting appointments beyond available capacity.',
            'Honour confirmed bookings.',
            'Update booking statuses accurately.',
            'Inform customers promptly of unavoidable changes.',
            'Avoid double-booking.',
          ],
        },
      ],
    },
    {
      heading: '6. Customer Service and Quality',
      blocks: [
        { text: 'Salon Partners are responsible for:' },
        {
          bullets: [
            'Providing services professionally.',
            'Maintaining reasonable hygiene and safety standards.',
            'Ensuring staff competence.',
            'Treating customers respectfully.',
            'Honouring confirmed service descriptions and prices.',
            'Handling complaints relating to the actual salon service.',
          ],
        },
      ],
    },
    {
      heading: '7. Payment Methods',
      blocks: [
        { text: 'Book A Look may support online payment and Pay at Store bookings.' },
        { lead: 'A. Online Payment' },
        { text: 'Where online payments are enabled:' },
        {
          bullets: [
            'Payments will be processed using the payment arrangement approved for the platform.',
            'The Salon Partner must comply with the applicable settlement and reconciliation process.',
            'The Salon Partner must not collect an additional amount for a service already paid in full online unless the customer has agreed to a legitimate additional service or charge.',
            'Refund responsibilities will follow the applicable partner agreement and refund workflow.',
          ],
        },
        {
          text: 'The precise collection, settlement, commission, gateway fee, and refund arrangement will be communicated separately to the Salon Partner.',
        },
        { lead: 'B. Pay at Store' },
        { text: 'Where Pay at Store is selected:' },
        {
          bullets: [
            'The customer pays the Salon Partner directly.',
            'The Salon Partner is responsible for collecting payment and issuing any applicable receipt.',
            'The Salon Partner must honour the price displayed at the time of booking, subject to customer-approved changes.',
            'Book A Look may record booking and payment status for platform administration.',
          ],
        },
      ],
    },
    {
      heading: '8. Commission and Subscription',
      blocks: [
        {
          text: 'Applicable commission rates, subscription charges, taxes, and settlement arrangements will be communicated through the selected partner plan or a separate commercial agreement.',
        },
        {
          text: 'No commission or fee shall be assumed unless it has been disclosed and accepted under the applicable partner arrangement.',
        },
      ],
    },
    {
      heading: '9. Cancellations and Salon-Initiated Changes',
      blocks: [
        { text: 'Salon Partners should avoid cancelling confirmed bookings except where reasonably necessary.' },
        { text: 'If a salon cannot honour an appointment, it must:' },
        {
          bullets: [
            'Inform the customer as soon as possible.',
            'Update the booking status through the platform.',
            'Cooperate with customer support.',
            'Assist with applicable refunds where the salon is responsible under the payment arrangement.',
          ],
        },
        {
          text: 'Repeated unjustified cancellations may result in reduced visibility, suspension, or removal from the platform.',
        },
      ],
    },
    {
      heading: '10. QR Check-in',
      blocks: [
        { text: 'Where QR check-in is enabled:' },
        {
          bullets: [
            'Each booking may have a unique QR code.',
            'The customer QR code becomes available 15 minutes before the appointment.',
            'The salon must use the authorized check-in functionality.',
            'QR codes must not be reused or manually manipulated.',
            'Booking completion must be recorded accurately.',
          ],
        },
      ],
    },
    {
      heading: '11. Customer Data and Confidentiality',
      blocks: [
        { text: 'Salon Partners may access customer information necessary to manage confirmed appointments.' },
        { text: 'They must:' },
        {
          bullets: [
            'Use customer information only for legitimate appointment-related purposes and other lawful purposes.',
            'Protect customer contact information.',
            'Avoid selling or sharing customer information without lawful authority.',
            'Avoid unsolicited marketing without the required permission.',
            'Secure devices and accounts used to access the partner platform.',
            'Comply with applicable data protection laws.',
          ],
        },
      ],
    },
    {
      heading: '12. Prohibited Conduct',
      blocks: [
        { text: 'Salon Partners must not:' },
        {
          bullets: [
            'Create fake bookings or reviews.',
            'Misrepresent services or prices.',
            'Manipulate appointment statuses.',
            'Misuse customer data.',
            'Circumvent agreed platform charges.',
            'Discriminate unlawfully against customers.',
            'Engage in fraudulent or misleading conduct.',
            'Upload content that infringes third-party rights.',
          ],
        },
      ],
    },
    {
      heading: '13. Suspension and Termination',
      blocks: [
        {
          text: 'Book A Look may investigate complaints and restrict or suspend partner accounts where there is evidence of fraud, repeated customer complaints, inaccurate listings, misuse of the platform, or violation of this policy.',
        },
        {
          text: 'Where practical, the Salon Partner will be informed of the concern and given an opportunity to respond.',
        },
      ],
    },
    {
      heading: '14. Complaints and Disputes',
      blocks: [
        { text: 'Salon Partners should first attempt to resolve customer service complaints fairly and promptly.' },
        { text: 'Platform-related concerns may be sent to:' },
        { text: CONTACT_EMAIL },
      ],
    },
    {
      heading: '15. Changes to This Policy',
      blocks: [
        {
          text: 'Book A Look may revise this policy from time to time. Updated terms will be communicated or published through the partner platform.',
        },
      ],
    },
  ],
};

// ------------------------------------------------------------ delete account

/**
 * Google Play requires apps that let users create an account to publish a web
 * page explaining how to request account deletion, and to link it from the
 * Data safety form. The customer steps mirror the in-app flow (Profile →
 * Delete Account → CustomerAuthController::deleteAccount, which anonymises the
 * profile and keeps booking/payment records). Partner accounts carry
 * settlements and dues, so they are closed on request by support.
 */
export const ACCOUNT_DELETION: LegalDocument = {
  slug: 'delete-account',
  title: 'Delete Your Account',
  kicker: 'Book A Look',
  summary:
    'How to delete your Book A Look customer or salon partner account, what is removed, and what is kept and why.',
  related: ALL_RELATED,
  sections: [
    {
      heading: '1. Customers — Delete From the App',
      blocks: [
        { text: 'You can delete your customer account yourself at any time from the Book A Look app:' },
        {
          bullets: [
            'Open the Book A Look app and sign in.',
            'Go to the Profile tab.',
            'Tap Delete Account at the bottom of the page.',
            'Confirm by tapping Delete.',
          ],
        },
        {
          text: `If you no longer have the app, email ${CONTACT_EMAIL} with the subject "Delete my account" and the mobile number registered with Book A Look. We may need to verify that the number belongs to you before deleting the account.`,
        },
      ],
    },
    {
      heading: '2. Salon Partners — Request Deletion',
      blocks: [
        {
          text: 'Salon partner accounts are closed by our support team, because pending bookings, settlements, and dues have to be resolved first. To request deletion:',
        },
        {
          bullets: [
            'In the Book A Look Partner app, open More → Delete Account to see these steps, or',
            `Email ${CONTACT_EMAIL} with the subject "Delete my partner account".`,
            'Include the salon name, owner name, and the mobile number registered with Book A Look.',
          ],
        },
        {
          text: 'We will verify the request with the registered owner, settle any outstanding bookings, payouts, or dues under the applicable partner arrangement, then close the account and remove the salon listing from Book A Look.',
        },
      ],
    },
    {
      heading: '3. What Is Deleted',
      blocks: [
        {
          bullets: [
            'Your name, mobile number, email address, address, pincode, and date of birth are removed from your profile.',
            'You are signed out of every device and the account can no longer be used to sign in.',
            'For salon partners, the salon listing is no longer shown to customers.',
          ],
        },
      ],
    },
    {
      heading: '4. What Is Kept and Why',
      blocks: [
        {
          text: 'Some records must be retained after an account is deleted, as described in our Privacy Policy:',
        },
        {
          bullets: [
            'Booking and appointment history, payment, refund, and invoice records — for accounting, tax, and legal requirements.',
            'Records relating to open disputes, refunds, or settlements — until they are resolved.',
            'Limited records needed to prevent fraud and ensure platform security.',
          ],
        },
        {
          text: 'Retained records are no longer linked to your name, mobile number, or email address, and are kept only as long as reasonably necessary or as required by applicable law.',
        },
      ],
    },
    {
      heading: '5. Need Help?',
      blocks: [{ text: 'For any question about deleting your account or your personal information, contact:' }, ...CONTACT_BLOCKS],
    },
  ],
};

// ---------------------------------------------------------------- about page

export const ABOUT: LegalDocument = {
  slug: 'about',
  title: 'About BookALook',
  kicker: 'India’s Smarter Way to Book Salon Appointments',
  summary:
    'BookALook is a modern online salon booking platform that helps customers discover trusted salons, book appointments instantly, and arrive at their scheduled time without unnecessary waiting.',
  related: ALL_RELATED,
  sections: [
    {
      heading: 'Why We Started BookALook',
      blocks: [
        {
          text: 'At BookALook, we believe your time is valuable. Standing in long salon queues or making multiple phone calls to check availability shouldn’t be part of your grooming experience.',
        },
        {
          text: 'BookALook is a modern online salon booking platform that helps customers discover trusted salons, book appointments instantly, and arrive at their scheduled time without unnecessary waiting. Our mission is simple:',
        },
        { text: 'No Waiting. Just Booking.' },
        {
          text: 'Whether you’re planning a quick haircut, beard styling, facial, hair spa, or any grooming service, BookALook makes the entire booking process fast, simple, and reliable.',
        },
      ],
    },
    {
      heading: 'The Problem',
      blocks: [
        { text: 'Millions of people visit salons every day, yet many still face the same challenges:' },
        {
          bullets: [
            'Long waiting times',
            'Uncertain appointment availability',
            'Last-minute scheduling issues',
            'Multiple phone calls to confirm bookings',
            'Lack of organized appointment management',
          ],
        },
        {
          text: 'We created BookALook to solve these everyday problems through technology that benefits both customers and salon businesses. Instead of waiting in crowded salons, customers can reserve their preferred time slot in advance and enjoy a smoother, more organized experience.',
        },
      ],
    },
    {
      heading: 'What Makes BookALook Different?',
      blocks: [
        {
          text: 'Unlike traditional salon directories or discount-focused platforms, BookALook is built around time management and customer convenience. Our platform offers:',
        },
        {
          bullets: [
            'Online salon appointment booking',
            'Real-time slot availability',
            'Instant booking confirmation',
            'WhatsApp booking notifications',
            'Secure QR-based salon check-in',
            'Easy cancellation and rescheduling within policy',
            'User-friendly experience for both customers and salons',
          ],
        },
        { text: 'We don’t just help you find a salon — we help you save time and make every visit more predictable.' },
      ],
    },
    {
      heading: 'For Customers',
      blocks: [
        { text: 'BookALook makes salon visits easier than ever. With just a few clicks, you can:' },
        {
          bullets: [
            'Find nearby salons',
            'Browse available services',
            'Choose your preferred appointment time',
            'Receive instant confirmation',
            'Check in quickly using your unique QR code',
            'Spend less time waiting and more time enjoying your day',
          ],
        },
      ],
    },
    {
      heading: 'For Salon Partners',
      blocks: [
        {
          text: 'BookALook is more than a booking platform — it’s a digital growth partner for salons. Our platform helps salon owners:',
        },
        {
          bullets: [
            'Manage appointments efficiently',
            'Reduce waiting queues',
            'Organize daily schedules',
            'Improve customer experience',
            'Increase online visibility',
            'Minimize booking conflicts',
            'Build stronger customer relationships',
          ],
        },
        {
          text: 'Whether you operate a small neighborhood salon or multiple branches, BookALook is designed to simplify operations and support business growth.',
        },
      ],
    },
    {
      heading: 'Our Vision',
      blocks: [
        {
          text: 'Our vision is to become India’s most trusted salon appointment platform by making every salon visit smarter, faster, and more convenient.',
        },
        {
          text: 'Starting from Maharashtra, we aim to build a connected ecosystem where customers enjoy organized appointments and salon businesses grow through technology. We believe the future of grooming is not about waiting — it’s about planning.',
        },
      ],
    },
    {
      heading: 'Our Mission',
      blocks: [
        {
          text: 'Our mission is to eliminate unnecessary waiting time from salon visits by providing a seamless digital booking experience that benefits customers and salon owners alike. Every feature we build is designed around one simple objective:',
        },
        { text: 'Making salon appointments easier, faster, and more reliable.' },
      ],
    },
    {
      heading: 'Powered by Technology',
      blocks: [
        { text: 'BookALook combines modern technology with everyday convenience. Our platform includes:' },
        {
          bullets: [
            'Smart appointment scheduling',
            'QR-based check-in system',
            'WhatsApp notifications',
            'Real-time booking management',
            'Secure customer data handling',
            'Scalable cloud-based infrastructure',
          ],
        },
        {
          text: 'These technologies help create a smooth experience from booking to check-in.',
        },
      ],
    },
    {
      heading: 'Join the BookALook Community',
      blocks: [
        {
          text: 'Whether you’re looking for your next haircut or want to grow your salon business, BookALook is here to make the experience effortless.',
        },
        {
          text: 'Discover trusted salons, book your preferred time, skip the waiting, and enjoy a smarter way to manage your grooming appointments.',
        },
        { text: 'No Waiting. Just Booking.' },
      ],
    },
  ],
};
