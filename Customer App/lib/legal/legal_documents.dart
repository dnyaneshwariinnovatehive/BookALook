// GENERATED FILE — DO NOT EDIT BY HAND.
//
// Produced by website/scripts/generate-legal-dart.mts from
// website/src/lib/legal.ts, which is transcribed from the approved policy
// documents. To change the wording, change legal.ts and re-run:
//
//   cd website && node --experimental-strip-types scripts/generate-legal-dart.mts
//
// Editing this file directly means the app and the website can say different
// things about the same policy, which is exactly the problem this file exists
// to prevent.

// The contact details the policy documents name. Kept as top-level constants
// because every "Contact us" section in the document set quotes them.
const String kLegalContactCompany = "BOOKALOOK PRIVATE LIMITED";
const String kLegalContactEmail = "bookalook01@gmail.com";
const String kLegalContactAddress = "PLOT NO 44 SR NO 17/22, DEVGIRI COLONY N-2, Aurangabad (MH), Aurangabad, Aurangabad- 431001, Maharashtra";

/// One paragraph, or a labelled sub-clause, or a bullet list.
class LegalBlock {
  const LegalBlock({this.lead, this.text, this.bullets});

  /// A bolded sub-clause label such as "C.1 Personal Information".
  final String? lead;

  final String? text;
  final List<String>? bullets;
}

class LegalSection {
  const LegalSection({required this.heading, required this.blocks});

  final String heading;
  final List<LegalBlock> blocks;
}

class LegalDocument {
  const LegalDocument({
    required this.slug,
    required this.title,
    required this.kicker,
    required this.summary,
    required this.related,
    required this.sections,
  });

  /// URL segment, so a document can be linked from a settings row and the
  /// viewer can title itself without being handed a second string.
  final String slug;
  final String title;
  final String kicker;

  /// One line under the title, and the "why should I read this" line.
  final String summary;

  /// Other documents worth reading, as a single string. The website renders
  /// these as separate links; in a phone settings list they are one line.
  final String related;

  final List<LegalSection> sections;
}

const List<LegalDocument> kLegalDocuments = [
  LegalDocument(
    slug: "terms",
    title: "Terms of Use",
    kicker: "BooKalook",
    summary: "These Terms of Use govern your access to and use of the BooKalook.in website, mobile application and related services.",
    related: "About BooKalook · Terms of Use · Privacy Policy · Cancellation & Refund Policy · Partner Terms & Conditions",
    sections: [
      LegalSection(
        heading: "A. Introduction",
        blocks: [
          LegalBlock(text: "Welcome to BooKalook.in (\"Company\", \"we\", \"our\", \"us\"). These Terms of Use (\"Terms\") govern your access to and use of our website, mobile application, and related services (collectively, the \"Platform\") that enable users to discover, schedule, and manage appointments with salons and beauty parlours (\"Services\")."),
          LegalBlock(text: "By accessing or using the Platform, you agree to be bound by these Terms and our Privacy Policy. If you do not agree, you must not use or access the Platform."),
        ],
      ),
      LegalSection(
        heading: "B. Eligibility",
        blocks: [
          LegalBlock(text: "You must be at least 18 years of age and capable of entering into a legally binding contract under the Indian Contract Act, 1872 to use our Platform. By using the Platform, you represent and warrant that you meet these eligibility requirements."),
        ],
      ),
      LegalSection(
        heading: "C. Platform Overview",
        blocks: [
          LegalBlock(text: "BooKalook.in provides an online appointment booking and discovery platform for salons, spas, and beauty parlours. The Platform connects users seeking grooming or beauty services (\"Customers\") with independent salon owners or professionals (\"Service Providers\")."),
          LegalBlock(text: "We do not own, operate, or control any salon or service listed on the Platform. Each Service Provider is solely responsible for its services, staff, pricing, availability, and quality standards."),
        ],
      ),
      LegalSection(
        heading: "D. Account Registration and Responsibilities",
        blocks: [
          LegalBlock(text: "To access booking features, you may be required to create an account by providing accurate personal information."),
          LegalBlock(text: "You are responsible for maintaining the confidentiality of your account credentials and for all activities that occur under your account."),
          LegalBlock(text: "You agree to immediately notify us of any unauthorised access or use of your account."),
          LegalBlock(text: "BooKalook.in reserves the right to suspend or terminate accounts suspected of misuse, fraudulent activity, or violation of these Terms."),
        ],
      ),
      LegalSection(
        heading: "E. Role of BooKalook.in",
        blocks: [
          LegalBlock(text: "BooKalook.in acts solely as a facilitator and intermediary between Customers and Service Providers."),
          LegalBlock(text: "All bookings are directly between the Customer and the Service Provider."),
          LegalBlock(text: "The Company is not responsible for:"),
          LegalBlock(bullets: [
            "The quality, timing, pricing, or completion of services.",
            "Any disputes or damages arising between Customers and Service Providers.",
            "The conduct or background of any Service Provider.",
          ]),
        ],
      ),
      LegalSection(
        heading: "F. User Obligations",
        blocks: [
          LegalBlock(text: "When using the Platform, you agree that you will not:"),
          LegalBlock(bullets: [
            "Post, transmit or share false, misleading, defamatory, obscene, or unlawful information.",
            "Attempt to hack, disable or interfere with the operation of the Platform.",
            "Use the Platform to solicit or promote illegal services.",
            "Resell, redistribute, or exploit the Platform for commercial gain without written consent.",
          ]),
        ],
      ),
      LegalSection(
        heading: "G. Booking, Payment and Pricing",
        blocks: [
          LegalBlock(text: "Customers can book appointments with listed salons through the Platform by selecting a preferred service, date and time."),
          LegalBlock(text: "Payments for confirmed bookings shall be processed through Razorpay, our authorised payment gateway."),
          LegalBlock(text: "The Company is not responsible for payment disputes arising from user error or failed transactions."),
          LegalBlock(text: "Taxes (including GST) are applied as per applicable law and may vary by salon and location."),
          LegalBlock(text: "A valid booking confirmation shall be issued upon successful payment or as per Service Provider policy."),
        ],
      ),
      LegalSection(
        heading: "H. Cancellation and Refund Policy",
        blocks: [
          LegalBlock(text: "Cancellations, rescheduling and refunds are governed by our Cancellation and Refund Policy, available separately on our Platform. By making a booking, you acknowledge that you have read and agreed to that policy."),
        ],
      ),
      LegalSection(
        heading: "I. Content and Intellectual Property",
        blocks: [
          LegalBlock(text: "All content on the Platform — including text, graphics, images, logos, software, and layout — is the exclusive property of BooKalook.in or its licensors and is protected under applicable copyright and trademark laws."),
          LegalBlock(text: "You may not copy, reproduce, modify, distribute or create derivative works from the Platform without prior written consent."),
          LegalBlock(text: "Any feedback, suggestions, or ideas submitted by users may be used by the Company without restriction or compensation."),
        ],
      ),
      LegalSection(
        heading: "J. Third-Party Services",
        blocks: [
          LegalBlock(text: "The Platform may contain links to third-party websites or integrate services from third-party providers (including payment gateways, analytics tools, etc.). BooKalook.in is not responsible for the content, terms, or privacy practices of such third parties."),
        ],
      ),
      LegalSection(
        heading: "K. Disclaimer of Warranties",
        blocks: [
          LegalBlock(text: "The Platform and its content are provided \"as is\" and \"as available\" without warranties of any kind, either express or implied. We do not warrant that:"),
          LegalBlock(bullets: [
            "The Platform will be uninterrupted or error-free.",
            "Information on the Platform will be accurate, current or reliable.",
            "Services provided by third parties will meet user expectations.",
          ]),
        ],
      ),
      LegalSection(
        heading: "L. Limitation of Liability",
        blocks: [
          LegalBlock(text: "To the fullest extent permitted by law, BooKalook.in shall not be liable for any direct, indirect, incidental, consequential, or punitive damages arising out of or relating to:"),
          LegalBlock(bullets: [
            "Use or inability to use the Platform;",
            "Any service, act, or omission of a salon or service provider;",
            "Loss of profits, data, goodwill, or other intangible losses.",
          ]),
          LegalBlock(text: "Our total liability, whether in contract, tort, or otherwise, shall not exceed the total amount paid by you for the relevant booking."),
        ],
      ),
      LegalSection(
        heading: "M. Indemnification",
        blocks: [
          LegalBlock(text: "You agree to indemnify, defend and hold harmless BooKalook.in, its partners, employees, affiliates, and service providers from any claims, liabilities, damages, or expenses (including legal fees) arising from your use of the Platform or violation of these Terms."),
        ],
      ),
      LegalSection(
        heading: "N. Termination",
        blocks: [
          LegalBlock(text: "We may suspend or terminate your account and access to the Platform at any time if we believe you have violated these Terms or engaged in fraudulent or harmful activities. Upon termination, all outstanding obligations or dues (if any) must be settled immediately."),
        ],
      ),
      LegalSection(
        heading: "O. Modifications to Terms",
        blocks: [
          LegalBlock(text: "BooKalook.in reserves the right to amend or update these Terms from time to time. Updated versions will be posted on the Platform with an effective date. Continued use of the Platform constitutes your acceptance of the revised Terms."),
        ],
      ),
      LegalSection(
        heading: "P. Governing Law and Jurisdiction",
        blocks: [
          LegalBlock(text: "These Terms are governed by the laws of India. Any disputes arising out of or in connection with these Terms shall be subject to the exclusive jurisdiction of the courts of Maharashtra, India."),
        ],
      ),
      LegalSection(
        heading: "Q. Contact Information",
        blocks: [
          LegalBlock(text: "For any queries, complaints, or notices regarding these Terms, please contact us at:"),
          LegalBlock(text: "BOOKALOOK PRIVATE LIMITED"),
          LegalBlock(text: "PLOT NO 44 SR NO 17/22, DEVGIRI COLONY N-2, Aurangabad (MH), Aurangabad, Aurangabad- 431001, Maharashtra"),
          LegalBlock(text: "bookalook01@gmail.com"),
        ],
      ),
    ],
  ),
  LegalDocument(
    slug: "privacy",
    title: "Privacy Policy",
    kicker: "BooKalook",
    summary: "This Privacy Policy sets out how BooKalook.in collects, uses, discloses and protects your personal information, in accordance with applicable laws of India.",
    related: "About BooKalook · Terms of Use · Privacy Policy · Cancellation & Refund Policy · Partner Terms & Conditions",
    sections: [
      LegalSection(
        heading: "A. Introduction",
        blocks: [
          LegalBlock(text: "BooKalook.in (\"Company\", \"we\", \"our\", \"us\") recognises the importance of the privacy of its users (\"you\", \"your\", \"User\") and the confidentiality of the information that you provide in the use of our website, platform, and related services (collectively, the \"Platform\"). This Privacy Policy sets out the practices for collection, use, disclosure and protection of your Personal Information in accordance with applicable laws of India."),
          LegalBlock(text: "By accessing or using our Platform, you agree to the terms and conditions of this Privacy Policy. If you do not agree with this Privacy Policy, please discontinue use of the Platform immediately."),
        ],
      ),
      LegalSection(
        heading: "B. Scope & Applicability",
        blocks: [
          LegalBlock(text: "This Privacy Policy applies to all Users of the Platform (including customers, salon partners, and service providers) and to all information collected via the Platform, its website, mobile application, and any offline channels operated by us. The Policy does not apply to any third-party website, apps or services that we do not control or operate."),
          LegalBlock(text: "You are advised to review the privacy policies of any such third-party services prior to use."),
        ],
      ),
      LegalSection(
        heading: "C. Information We Collect",
        blocks: [
          LegalBlock(lead: "C.1 Personal Information"),
          LegalBlock(text: "We may collect the following types of Personal Information:"),
          LegalBlock(bullets: [
            "Full name, phone number, email address, location/address.",
            "Appointment, booking and service usage history and preferences.",
          ]),
          LegalBlock(lead: "C.2 Non-Personal / Aggregate Information"),
          LegalBlock(text: "We may also collect information that does not identify you personally, including:"),
          LegalBlock(bullets: [
            "Device information (type, operating system, browser), IP address, date/time of visit, usage patterns, cookies and analytics data.",
          ]),
          LegalBlock(lead: "C.3 Payment Information"),
          LegalBlock(text: "Payments are processed via our authorised payment gateway partner (Razorpay). We do not store or access your full payment card or bank account details; only minimal transaction information may be retained for record-keeping."),
        ],
      ),
      LegalSection(
        heading: "D. Purposes for Collection and Legal Basis",
        blocks: [
          LegalBlock(text: "We collect, use and process your information for the following purposes:"),
          LegalBlock(bullets: [
            "To enable you to make salon or parlour appointments and related services via the Platform.",
            "To send confirmations, reminders, updates, and notifications regarding your booking or service.",
            "To administer your account, profile and preferences and to personalise your experience on the Platform.",
            "To conduct analytics and improve the Platform's design, features, performance and functionality.",
            "To send you promotional offers, marketing communications, subject to your consent where required.",
            "To comply with applicable laws, prevent fraud, misuse or other illegal or unauthorised activities.",
          ]),
        ],
      ),
      LegalSection(
        heading: "E. Cookies and Similar Technologies",
        blocks: [
          LegalBlock(text: "Our Platform uses cookies, web beacons, tracking pixels and similar technologies to remember your preferences, maintain your session and compile aggregate usage information. These allow us to personalise your experience and improve the Platform."),
          LegalBlock(text: "You may disable cookies via your browser settings, but this may limit your ability to use certain features of the Platform."),
        ],
      ),
      LegalSection(
        heading: "F. Sharing, Disclosure and Transfer of Information",
        blocks: [
          LegalBlock(text: "We do not sell or rent your Personal Information. We may share your information as follows:"),
          LegalBlock(bullets: [
            "With salon partners / service providers (to facilitate your booking and service fulfilment).",
            "With payment gateway and financial institutions (for payment processing and refunds).",
            "With third-party service providers (analytics, hosting, support) under appropriate confidentiality obligations.",
            "With legal, regulatory or governmental authorities when required by law or court order.",
            "In connection with business transfers or restructuring; your data may be transferred to an acquirer subject to the acquirer's obligations in respect of confidentiality.",
          ]),
          LegalBlock(text: "If your information is transferred outside India for processing, we will ensure such processing is subject to appropriate safeguards."),
        ],
      ),
      LegalSection(
        heading: "G. How Long Do We Keep Your Personal Information?",
        blocks: [
          LegalBlock(text: "We retain your Personal Information for as long as is necessary for the purposes described above, or as required by law (such as taxation, accounting or regulatory retention). Once no longer required, your information will be anonymised or securely deleted."),
        ],
      ),
      LegalSection(
        heading: "H. Data Security",
        blocks: [
          LegalBlock(text: "We implement commercially reasonable technical, physical and administrative safeguards to protect your Personal Information against unauthorised access, alteration, disclosure or destruction. However, no method of transmission over the internet or electronic storage is completely secure; we cannot guarantee absolute security."),
        ],
      ),
      LegalSection(
        heading: "I. Your Rights and Choices",
        blocks: [
          LegalBlock(text: "You have the right to:"),
          LegalBlock(bullets: [
            "Access or request a copy of the Personal Information we hold about you.",
            "Request correction, update or deletion of your Personal Information (subject to legal or contractual restrictions).",
            "Withdraw your consent for processing where such processing is based on consent (for example, marketing communications).",
            "Object to or restrict certain processing of your Personal Information.",
          ]),
          LegalBlock(text: "To exercise your rights, or if you have any queries, you may contact us at bookalook01@gmail.com. We may require verification of your identity before processing requests."),
        ],
      ),
      LegalSection(
        heading: "J. Children's Privacy",
        blocks: [
          LegalBlock(text: "The Platform is not intended for use by children under the age of 18. We do not knowingly collect Personal Information of children under 18. If you believe we have inadvertently collected such information, please contact us and we will take steps to delete such information."),
        ],
      ),
      LegalSection(
        heading: "K. Third-Party Links and Content",
        blocks: [
          LegalBlock(text: "The Platform may contain links to third-party websites, applications or services not operated or controlled by us. We do not assume any responsibility for their privacy practices, content or availability. You are strongly advised to review their respective privacy policies."),
        ],
      ),
      LegalSection(
        heading: "L. Withdrawal of Consent, Account Deletion & Data Access",
        blocks: [
          LegalBlock(text: "You may withdraw your consent at any time to our collection, use or disclosure of your Personal Information, subject to certain limitations (for example, if data is required to fulfil an ongoing booking). To request deletion of your account or data, contact bookalook01@gmail.com. Please note that we may retain certain transactional or service-fulfilment data as required by applicable law."),
        ],
      ),
      LegalSection(
        heading: "M. Changes to this Privacy Policy",
        blocks: [
          LegalBlock(text: "This Privacy Policy may be updated from time to time to reflect changes in our practices or legal/regulatory requirements. Any changes will be posted on this page with an updated \"Effective Date\". Continued use of the Platform after such changes constitutes your acceptance of the revised policy."),
        ],
      ),
      LegalSection(
        heading: "N. Governing Law and Jurisdiction",
        blocks: [
          LegalBlock(text: "This Privacy Policy is governed by the laws of India. Any disputes or claims arising out of or in connection with this Privacy Policy shall be subject to the exclusive jurisdiction of the courts of Maharashtra, India."),
        ],
      ),
      LegalSection(
        heading: "O. Contact Us",
        blocks: [
          LegalBlock(text: "If you have any questions, concerns or requests regarding this Privacy Policy or your Personal Information, you may contact us at:"),
          LegalBlock(text: "BOOKALOOK PRIVATE LIMITED"),
          LegalBlock(text: "PLOT NO 44 SR NO 17/22, DEVGIRI COLONY N-2, Aurangabad (MH), Aurangabad, Aurangabad- 431001, Maharashtra"),
          LegalBlock(text: "bookalook01@gmail.com"),
        ],
      ),
    ],
  ),
  LegalDocument(
    slug: "cancellation-refund",
    title: "Cancellation & Refund Policy",
    kicker: "BooKalook",
    summary: "How cancellations, rescheduling and refunds work for appointments booked through BooKalook.in.",
    related: "About BooKalook · Terms of Use · Privacy Policy · Cancellation & Refund Policy · Partner Terms & Conditions",
    sections: [
      LegalSection(
        heading: "A. Introduction",
        blocks: [
          LegalBlock(text: "This Cancellation and Refund Policy (\"Policy\") describes the terms under which BooKalook.in (\"Company\", \"we\", \"our\", \"us\") permits cancellation, rescheduling, and refund of appointments booked through our website or mobile application (\"Platform\")."),
          LegalBlock(text: "By booking an appointment via BooKalook.in, the user (\"Customer\", \"you\", \"your\") acknowledges and agrees to the terms stated herein."),
        ],
      ),
      LegalSection(
        heading: "B. Cancellation Policy",
        blocks: [
          LegalBlock(lead: "Customer-Initiated Cancellations"),
          LegalBlock(text: "You may cancel an appointment at any point before the cancellation window shown on your booking closes."),
          LegalBlock(text: "Cancellations made before that window closes are eligible for a full refund of the booking amount."),
          LegalBlock(text: "Cancellations made once that window has closed are not eligible for any refund."),
          LegalBlock(lead: "Service Provider Cancellations"),
          LegalBlock(text: "In the unlikely event that a salon or service provider cancels your confirmed appointment, you will be entitled to a full refund or, at your discretion, a rescheduled appointment at no extra charge."),
          LegalBlock(lead: "Platform Cancellations"),
          LegalBlock(text: "BooKalook.in reserves the right to cancel a booking for operational, technical, or compliance reasons. In such cases, a full refund shall be processed to the original payment method."),
        ],
      ),
      LegalSection(
        heading: "C. Rescheduling Policy",
        blocks: [
          LegalBlock(text: "Customers are permitted to reschedule a booking only once."),
          LegalBlock(text: "Once a booking has been rescheduled, it cannot be cancelled or rescheduled again under any circumstance."),
          LegalBlock(text: "Rescheduling is subject to slot availability and approval by the service provider."),
        ],
      ),
      LegalSection(
        heading: "D. Refund Process",
        blocks: [
          LegalBlock(text: "Refunds (where applicable) shall be initiated within 5-7 business days after cancellation confirmation."),
          LegalBlock(text: "All refunds shall be credited to the original mode of payment used during the booking (e.g., Razorpay, credit/debit card, UPI, net banking)."),
          LegalBlock(text: "The actual credit to the customer's account may take additional time depending on the payment gateway and the customer's bank policies."),
          LegalBlock(text: "The Company is not responsible for any delay caused by third-party payment processors."),
        ],
      ),
      LegalSection(
        heading: "E. Non-Refundable Scenarios",
        blocks: [
          LegalBlock(text: "Refunds shall not be applicable in the following cases:"),
          LegalBlock(bullets: [
            "Cancellations made once the cancellation window shown on your booking has closed.",
            "\"No-Show\" situations where the customer fails to appear at the salon at the scheduled time.",
            "Situations where services were rendered but not up to personal expectation (quality issues must be raised directly with the salon).",
            "Multiple reschedule requests for the same booking.",
          ]),
        ],
      ),
      LegalSection(
        heading: "F. Special Conditions / Force Majeure",
        blocks: [
          LegalBlock(text: "In case of unforeseen circumstances such as natural disasters, government restrictions, internet outages, or technical failures beyond the Company's control, BooKalook.in reserves the right to cancel or reschedule bookings without liability. Refund eligibility in such cases shall be determined at the Company's sole discretion."),
        ],
      ),
      LegalSection(
        heading: "G. Contact for Refund Support",
        blocks: [
          LegalBlock(text: "For refund or cancellation queries, please contact our support team at:"),
          LegalBlock(text: "bookalook01@gmail.com"),
          LegalBlock(text: "Our support team will respond to refund-related queries within 2-3 working days."),
        ],
      ),
      LegalSection(
        heading: "H. Modification of Policy",
        blocks: [
          LegalBlock(text: "BooKalook.in reserves the right to modify, amend, or update this Policy at any time without prior notice. The updated Policy shall be posted on the Platform with a revised effective date. Your continued use of the Platform after such updates constitutes acceptance of the revised terms."),
        ],
      ),
      LegalSection(
        heading: "I. Governing Law and Jurisdiction",
        blocks: [
          LegalBlock(text: "This Policy shall be governed by and construed in accordance with the laws of India. Any disputes arising from or related to this Policy shall be subject to the exclusive jurisdiction of the courts of Maharashtra, India."),
        ],
      ),
    ],
  ),
  LegalDocument(
    slug: "partner-terms",
    title: "Partner Terms & Conditions",
    kicker: "BooKalook for Salons",
    summary: "The agreement between BooKalook.in and every salon, parlour or individual stylist who lists and provides services on the platform.",
    related: "About BooKalook · Terms of Use · Privacy Policy · Cancellation & Refund Policy · Partner Terms & Conditions",
    sections: [
      LegalSection(
        heading: "1. Introduction",
        blocks: [
          LegalBlock(text: "These Partner Terms and Conditions (\"Agreement\") govern the relationship between BooKalook.in (\"Platform\", \"Company\", \"We\", \"Our\", \"Us\") and each salon, parlour, or individual stylist (\"Partner\", \"You\", \"Your\") who lists and provides services through the BooKalook.in platform."),
          LegalBlock(text: "By registering as a Partner, You acknowledge that You have read, understood, and agreed to be bound by the terms of this Agreement, the Privacy Policy, and the general Terms of Use available on BooKalook.in."),
        ],
      ),
      LegalSection(
        heading: "2. Registration & Onboarding",
        blocks: [
          LegalBlock(text: "Partners must provide accurate and verifiable details during registration, including business name, address, GST number, and owner identification."),
          LegalBlock(text: "BooKalook.in reserves the right to verify such information and approve or reject onboarding requests at its discretion."),
          LegalBlock(text: "The Partner shall be responsible for maintaining and updating its information to ensure it remains true and accurate at all times."),
        ],
      ),
      LegalSection(
        heading: "3. Services & Listing Responsibilities",
        blocks: [
          LegalBlock(text: "Partners are solely responsible for the accuracy of their service descriptions, prices, offers, and images displayed on the platform."),
          LegalBlock(text: "BooKalook.in shall not be liable for any misrepresentation or outdated information provided by the Partner."),
          LegalBlock(text: "Partners must update their service availability regularly to prevent double bookings or schedule conflicts."),
        ],
      ),
      LegalSection(
        heading: "4. Booking, Cancellations & Customer Handling",
        blocks: [
          LegalBlock(text: "Partners agree to honour all confirmed bookings received through the platform."),
          LegalBlock(text: "Any cancellation by the Partner must be immediately communicated to both the customer and BooKalook.in."),
          LegalBlock(text: "Repeated cancellations, delays, or customer complaints may lead to temporary suspension or permanent delisting from the platform."),
        ],
      ),
      LegalSection(
        heading: "5. Fees, Commissions & Subscriptions",
        blocks: [
          LegalBlock(text: "BooKalook.in may charge subscription fees or commissions on bookings made through the platform."),
          LegalBlock(text: "The applicable commission or subscription structure will be communicated via the Partner Dashboard or onboarding process."),
          LegalBlock(text: "All such fees are exclusive of GST and applicable taxes under Indian law."),
        ],
      ),
      LegalSection(
        heading: "6. Payments & Settlements",
        blocks: [
          LegalBlock(text: "Payments to Partners will be made after deducting platform commissions, taxes, and other applicable charges."),
          LegalBlock(text: "Settlements will occur on a defined payment cycle as communicated by BooKalook.in."),
          LegalBlock(text: "BooKalook.in shall not be liable for delays arising from banking networks, Razorpay, or other payment intermediaries."),
        ],
      ),
      LegalSection(
        heading: "7. Compliance & Standards",
        blocks: [
          LegalBlock(text: "Partners must comply with all relevant laws, including labour, taxation, hygiene, and safety regulations. Salons must ensure:"),
          LegalBlock(bullets: [
            "Proper hygiene and sanitisation of tools and equipment.",
            "Professional and courteous staff behaviour.",
            "Compliance with applicable local municipal or state health laws.",
          ]),
          LegalBlock(text: "BooKalook.in may remove any Partner who fails to maintain the required quality standards."),
        ],
      ),
      LegalSection(
        heading: "8. Ratings & Reviews",
        blocks: [
          LegalBlock(text: "Customers can rate and review Partner services on the platform."),
          LegalBlock(text: "BooKalook.in reserves the right to display, remove, or moderate reviews at its discretion."),
          LegalBlock(text: "Repeated negative feedback or verified complaints may result in suspension or delisting."),
        ],
      ),
      LegalSection(
        heading: "9. Intellectual Property",
        blocks: [
          LegalBlock(text: "Partners grant BooKalook.in a non-exclusive, royalty-free licence to use their business name, logo, photos, and descriptions for marketing and listing purposes."),
          LegalBlock(text: "Partners shall not use BooKalook.in's name, logo, or brand assets without prior written consent."),
        ],
      ),
      LegalSection(
        heading: "10. Termination",
        blocks: [
          LegalBlock(text: "Either party may terminate this Agreement with 30 days' written notice."),
          LegalBlock(text: "BooKalook.in may terminate immediately for material breaches, fraud, or repeated service failures."),
          LegalBlock(text: "Upon termination, all outstanding dues must be settled before account closure."),
        ],
      ),
      LegalSection(
        heading: "11. Indemnity & Liability",
        blocks: [
          LegalBlock(text: "The Partner agrees to indemnify and hold BooKalook.in harmless from any claims, damages, or losses arising out of:"),
          LegalBlock(bullets: [
            "Non-performance or service issues.",
            "Breach of applicable laws.",
            "Customer disputes relating to the Partner's actions.",
          ]),
          LegalBlock(text: "BooKalook.in's liability under this Agreement shall be limited to the amount of commission earned from the disputed transaction."),
        ],
      ),
      LegalSection(
        heading: "12. Governing Law",
        blocks: [
          LegalBlock(text: "This Agreement shall be governed by and construed in accordance with the laws of India. The courts at Chhatrapati Sambhajinagar, Maharashtra shall have exclusive jurisdiction."),
        ],
      ),
      LegalSection(
        heading: "13. Service Level Agreement (SLA)",
        blocks: [
          LegalBlock(text: "Partners must maintain punctuality, hygiene, and professional conduct at all times."),
          LegalBlock(text: "BooKalook.in may conduct quality checks and customer surveys to ensure service standards."),
          LegalBlock(text: "Breach of SLA terms may result in penalties, temporary suspension, or removal from the platform."),
        ],
      ),
      LegalSection(
        heading: "14. Non-Solicitation & Platform Integrity",
        blocks: [
          LegalBlock(text: "Partners shall not directly approach, solicit, or induce BooKalook.in customers to transact outside the platform."),
          LegalBlock(text: "Any circumvention of platform booking, manipulation of pricing, or fee avoidance shall constitute a material breach, leading to termination and potential damages recovery."),
        ],
      ),
      LegalSection(
        heading: "15. Confidentiality",
        blocks: [
          LegalBlock(text: "Both parties shall keep all non-public data, including customer information and platform analytics, strictly confidential."),
          LegalBlock(text: "Partners may use customer data only for service fulfilment, not for direct marketing or third-party sharing."),
          LegalBlock(text: "BooKalook.in will handle partner data in compliance with applicable Indian data protection and IT laws."),
        ],
      ),
      LegalSection(
        heading: "16. Dispute Resolution",
        blocks: [
          LegalBlock(text: "Disputes shall first be resolved amicably through discussion within 30 days."),
          LegalBlock(text: "If unresolved, disputes will be referred to binding arbitration under the Arbitration and Conciliation Act, 1996."),
          LegalBlock(text: "The arbitration venue shall be Chhatrapati Sambhajinagar, Maharashtra, and proceedings shall be conducted in English."),
        ],
      ),
      LegalSection(
        heading: "17. Contact",
        blocks: [
          LegalBlock(text: "For partner support, clarifications, or legal queries, please reach out to:"),
          LegalBlock(text: "bookalook01@gmail.com"),
        ],
      ),
    ],
  ),
  LegalDocument(
    slug: "about",
    title: "About BooKalook",
    kicker: "India’s Smarter Way to Book Salon Appointments",
    summary: "BooKalook is a modern online salon booking platform that helps customers discover trusted salons, book appointments instantly, and arrive at their scheduled time without unnecessary waiting.",
    related: "About BooKalook · Terms of Use · Privacy Policy · Cancellation & Refund Policy · Partner Terms & Conditions",
    sections: [
      LegalSection(
        heading: "Why We Started BooKalook",
        blocks: [
          LegalBlock(text: "At BooKalook, we believe your time is valuable. Standing in long salon queues or making multiple phone calls to check availability shouldn’t be part of your grooming experience."),
          LegalBlock(text: "BooKalook is a modern online salon booking platform that helps customers discover trusted salons, book appointments instantly, and arrive at their scheduled time without unnecessary waiting. Our mission is simple:"),
          LegalBlock(text: "No Waiting. Just Booking."),
          LegalBlock(text: "Whether you’re planning a quick haircut, beard styling, facial, hair spa, or any grooming service, BooKalook makes the entire booking process fast, simple, and reliable."),
        ],
      ),
      LegalSection(
        heading: "The Problem",
        blocks: [
          LegalBlock(text: "Millions of people visit salons every day, yet many still face the same challenges:"),
          LegalBlock(bullets: [
            "Long waiting times",
            "Uncertain appointment availability",
            "Last-minute scheduling issues",
            "Multiple phone calls to confirm bookings",
            "Lack of organized appointment management",
          ]),
          LegalBlock(text: "We created BooKalook to solve these everyday problems through technology that benefits both customers and salon businesses. Instead of waiting in crowded salons, customers can reserve their preferred time slot in advance and enjoy a smoother, more organized experience."),
        ],
      ),
      LegalSection(
        heading: "What Makes BooKalook Different?",
        blocks: [
          LegalBlock(text: "Unlike traditional salon directories or discount-focused platforms, BooKalook is built around time management and customer convenience. Our platform offers:"),
          LegalBlock(bullets: [
            "Online salon appointment booking",
            "Real-time slot availability",
            "Instant booking confirmation",
            "WhatsApp booking notifications",
            "Secure QR-based salon check-in",
            "Easy cancellation and rescheduling within policy",
            "User-friendly experience for both customers and salons",
          ]),
          LegalBlock(text: "We don’t just help you find a salon — we help you save time and make every visit more predictable."),
        ],
      ),
      LegalSection(
        heading: "For Customers",
        blocks: [
          LegalBlock(text: "BooKalook makes salon visits easier than ever. With just a few clicks, you can:"),
          LegalBlock(bullets: [
            "Find nearby salons",
            "Browse available services",
            "Choose your preferred appointment time",
            "Receive instant confirmation",
            "Check in quickly using your unique QR code",
            "Spend less time waiting and more time enjoying your day",
          ]),
        ],
      ),
      LegalSection(
        heading: "For Salon Partners",
        blocks: [
          LegalBlock(text: "BooKalook is more than a booking platform — it’s a digital growth partner for salons. Our platform helps salon owners:"),
          LegalBlock(bullets: [
            "Manage appointments efficiently",
            "Reduce waiting queues",
            "Organize daily schedules",
            "Improve customer experience",
            "Increase online visibility",
            "Minimize booking conflicts",
            "Build stronger customer relationships",
          ]),
          LegalBlock(text: "Whether you operate a small neighborhood salon or multiple branches, BooKalook is designed to simplify operations and support business growth."),
        ],
      ),
      LegalSection(
        heading: "Our Vision",
        blocks: [
          LegalBlock(text: "Our vision is to become India’s most trusted salon appointment platform by making every salon visit smarter, faster, and more convenient."),
          LegalBlock(text: "Starting from Maharashtra, we aim to build a connected ecosystem where customers enjoy organized appointments and salon businesses grow through technology. We believe the future of grooming is not about waiting — it’s about planning."),
        ],
      ),
      LegalSection(
        heading: "Our Mission",
        blocks: [
          LegalBlock(text: "Our mission is to eliminate unnecessary waiting time from salon visits by providing a seamless digital booking experience that benefits customers and salon owners alike. Every feature we build is designed around one simple objective:"),
          LegalBlock(text: "Making salon appointments easier, faster, and more reliable."),
        ],
      ),
      LegalSection(
        heading: "Powered by Technology",
        blocks: [
          LegalBlock(text: "BooKalook combines modern technology with everyday convenience. Our platform includes:"),
          LegalBlock(bullets: [
            "Smart appointment scheduling",
            "QR-based check-in system",
            "WhatsApp notifications",
            "Real-time booking management",
            "Secure customer data handling",
            "Scalable cloud-based infrastructure",
          ]),
          LegalBlock(text: "These technologies help create a smooth experience from booking to check-in."),
        ],
      ),
      LegalSection(
        heading: "Join the BooKalook Community",
        blocks: [
          LegalBlock(text: "Whether you’re looking for your next haircut or want to grow your salon business, BooKalook is here to make the experience effortless."),
          LegalBlock(text: "Discover trusted salons, book your preferred time, skip the waiting, and enjoy a smarter way to manage your grooming appointments."),
          LegalBlock(text: "No Waiting. Just Booking."),
        ],
      ),
    ],
  ),
];

/// Look a document up by [slug]. Returns null for an unknown slug so a bad
/// route degrades to an empty screen rather than throwing on a user.
LegalDocument? legalDocumentBySlug(String slug) {
  for (final doc in kLegalDocuments) {
    if (doc.slug == slug) return doc;
  }
  return null;
}
