"use client";

import { useEffect, useState } from 'react';
import {
  BANK_FIELD_LABELS,
  EMPTY_BANK_DETAILS,
  bankDetailsPayload,
  validateBankDetails,
  type BankDetailsInput,
} from '@/lib/bankDetails';
import StoreBadge from '@/components/site/StoreBadge';
import PricingSection from './PricingSection';
import { CountUp, Parallax, QrCode, Reveal, RotatingWord, useOrigin } from './motion';
import s from './landing.module.css';
import {
  CUSTOMER_APP_STORE_URL,
  CUSTOMER_PLAY_STORE_URL,
  PARTNER_APP_STORE_URL,
  PARTNER_PLAY_STORE_URL,
} from '@/lib/site-links';

/* ============================================================================
   BOOKALOOK LANDING — written for salon owners, the people who buy plans.
   Customers still have their own section further down: they are why an owner
   joins. The salon enquiry form is kept as it was and only framed here.

   The header and footer live in `../layout.tsx`, and the store URLs in
   `@/lib/site-links`, so this file is only the page body.
   ============================================================================ */

/** What owners stop losing, and what replaces it. */
const GAINS = [
  {
    pain: 'No-shows and last-minute ghosts',
    title: 'Advance payments hold every slot',
    desc: 'Customers pay a small advance to book, so they turn up. If they do not, the advance is yours.',
  },
  {
    pain: 'Empty chairs on weekday afternoons',
    title: 'New customers find you in the app',
    desc: 'Your salon, services and live free slots are listed for customers searching nearby, every hour of the day.',
  },
  {
    pain: 'Registers, calls and WhatsApp chaos',
    title: 'One app runs the whole salon',
    desc: 'Bookings, walk-ins, staff hours, billing, payouts and reports — on your phone, for every branch.',
  },
];

const OWNER_FEATURES = [
  { icon: 'check-calendar', title: 'Online bookings, no double-booking', desc: 'Real-time availability per stylist, so a slot is only ever sold once.' },
  { icon: 'lock', title: 'Secure advance payments', desc: 'Advances are collected online and adjusted against the final bill.' },
  { icon: 'users', title: 'Staff, hours and leave', desc: 'Shifts, breaks and leave per person. Change salon hours and staff follow.' },
  { icon: 'bag', title: 'Walk-ins and billing', desc: 'Add walk-ins, add services mid-visit, collect payment and send invoices.' },
  { icon: 'qr', title: 'QR check-in', desc: 'Customers scan at the door; you know who is in the chair and when.' },
  { icon: 'chat', title: 'Booking updates on WhatsApp', desc: 'Confirmations and reminders go to customers automatically.' },
  { icon: 'trend', title: 'Revenue insights', desc: 'See busy hours, best services and quiet stylists — and what to do next.' },
  { icon: 'wallet', title: 'Payouts and reward coins', desc: 'Online advances paid to your bank, plus coins you can put towards your plan.' },
];

const START_STEPS = [
  { title: 'Send the form below', desc: 'Two minutes: your salon, area and contact. Bank details are optional.' },
  { title: 'We verify your salon', desc: 'Our team checks the details, usually with a quick visit or call.' },
  { title: 'Pick your plan', desc: 'A monthly plan, or the Commission Model. Use your welcome coins towards it.' },
  { title: 'Go live and take bookings', desc: 'Set up services and staff in the Partner App and start receiving bookings.' },
];

const SALON_ROLES = [
  {
    tag: 'Salon owner',
    title: 'Run every branch',
    desc: 'Bookings, staff, services, payouts and reports for each of your salons — switch between branches in one tap.',
  },
  {
    tag: 'Stylists & staff',
    title: 'Their day, on their phone',
    desc: 'Each stylist sees their own appointments, checks customers in, adds walk-ins and requests leave.',
  },
  {
    tag: 'Collaborator',
    title: 'Help on the ground',
    desc: 'A BookALook field partner helps you get set up and stays your point of contact.',
  },
];

/** The floating "stickers" that drift with the scroll, Zomato-style. */
const STICKERS = [
  { emoji: '✂️', label: 'Haircut' },
  { emoji: '💅', label: 'Nails' },
  { emoji: '💆', label: 'Facial' },
  { emoji: '🧖', label: 'Spa' },
  { emoji: '🧔', label: 'Beard' },
  { emoji: '💇', label: 'Hair colour' },
  { emoji: '💄', label: 'Makeup' },
  { emoji: '🪮', label: 'Styling' },
];

const HERO_WORDS = ['haircut', 'facial', 'manicure', 'hair spa', 'beard trim', 'bridal look'];

/** The two rows of the hero ticker; they scroll in opposite directions. */
const TICKER_ROWS = [
  [
    { icon: 'scissors', label: 'Haircut' },
    { icon: 'spark', label: 'Facial' },
    { icon: 'hand', label: 'Manicure' },
    { icon: 'droplet', label: 'Hair spa' },
    { icon: 'brush', label: 'Makeup' },
    { icon: 'crown', label: 'Bridal' },
  ],
  [
    { icon: 'razor', label: 'Beard trim' },
    { icon: 'palette', label: 'Hair colour' },
    { icon: 'leaf', label: 'Spa' },
    { icon: 'comb', label: 'Styling' },
    { icon: 'hand', label: 'Pedicure' },
    { icon: 'spark', label: 'Clean-up' },
  ],
];

const HERO_TRUST = ['Verified salons', 'Live free slots', 'QR check-in', '₹0 booking fee'];

/** "What's waiting for you on the app?" — tiles around the phone. */
const APP_FEATURES = [
  { emoji: '⏱️', title: 'Live free slots', desc: 'See exactly when your stylist is free.' },
  { emoji: '🔒', title: 'Small advance', desc: 'Pay a little to lock your slot. The rest at the salon.' },
  { emoji: '📲', title: 'QR check-in', desc: 'Scan at the door and walk straight in.' },
  { emoji: '💬', title: 'WhatsApp updates', desc: 'Confirmation and a reminder before you go.' },
  { emoji: '🎁', title: 'First-visit offers', desc: 'Welcome discounts at salons new to you.' },
  { emoji: '⭐', title: 'Real ratings', desc: 'Reviews from people who actually visited.' },
  { emoji: '👨‍👩‍👧', title: 'Book for family', desc: 'Book for your partner, parents or kids.' },
  { emoji: '❤️', title: 'Favourites', desc: 'Rebook your go-to salon in two taps.' },
];

const CUSTOMER_STATS = [
  { prefix: '₹', to: 0, suffix: '', label: 'booking fee', icon: '🏷️' },
  { prefix: '', to: 24, suffix: '×7', label: 'book any time', icon: '🕒' },
  { prefix: '', to: 100, suffix: '%', label: 'salons verified', icon: '✅' },
  { prefix: '', to: 1, suffix: '-tap', label: 'QR check-in', icon: '📲' },
];

const CUSTOMER_STEPS = [
  { emoji: '🔍', title: 'Find a salon', desc: 'Browse verified salons by area, service, price and rating.' },
  { emoji: '🗓️', title: 'Pick a time', desc: 'Choose your stylist and a live free slot. Pay a small advance.' },
  { emoji: '✨', title: 'Walk in, look great', desc: 'Show your QR at the door. No waiting bench, no confusion.' },
];

// [PLACEHOLDER] Customer FAQ answers are provisional copy — confirm with the business team.
const CUSTOMER_FAQ = [
  {
    q: 'Does BookALook charge customers a booking fee?',
    a: 'No. You pay the salon’s price. A small part of it is paid online as an advance to hold your slot, and the rest at the salon.',
  },
  {
    q: 'What if I need to cancel or reschedule?',
    a: 'You can cancel or reschedule from the app up to the salon’s cutoff time, shown before you book. Refunds follow the cancellation policy; if the salon cancels, you get your advance back.',
  },
  {
    q: 'How does QR check-in work?',
    a: 'Every booking has a QR code in the app. Show it at the salon and they check you in — no names to spell out, no token numbers.',
  },
  {
    q: 'Can I book for someone else?',
    a: 'Yes. Choose “someone else” at checkout and add their name, so the salon knows who to expect.',
  },
];

// [PLACEHOLDER] FAQ answers are provisional copy — confirm with the business team.
const FAQ_ITEMS = [
  {
    q: 'How much does BookALook cost my salon?',
    a: 'Choose a monthly Subscription Plan (the current plans and prices are shown above, straight from our system), or the Commission Model, where there is no monthly fee and you pay an agreed percentage on app bookings only. Walk-ins are never charged commission.',
  },
  {
    q: 'How do the customer advances reach me?',
    a: 'Customers pay their advance online when they book. BookALook holds it and pays it out to your bank: weekly for plan salons, monthly for Commission Model salons (after the commission for that month). The rest of the bill is paid to you at the counter.',
  },
  {
    q: 'What if a customer does not show up?',
    a: 'The advance they paid is kept as compensation for the lost slot and reaches you in your payout. Your cancellation window is shown to customers before they book.',
  },
  {
    q: 'Can my staff use it, and do I need a separate app?',
    a: 'One Partner App serves everyone. You log in as the owner; each stylist logs in with their own number and sees only their own work. If you run more than one salon, you switch between them in the same app.',
  },
  {
    q: 'Do I need bank details to register?',
    a: 'No. You can register and go live without them, and add them later from the Partner App. They are only needed before your first payout.',
  },
  {
    q: 'How do I become a Collaborator?',
    a: 'Collaborators are field partners who help salons in their area join and stay supported. Email hello@bookalook.in and our team will walk you through it.',
  },
];

// [PLACEHOLDER] All review copy below is INVENTED SAMPLE CONTENT — these are not
// real people and must not be published as genuine testimonials. Replace every
// entry with verified, consented reviews (or wire the section to the real review
// API) before going live. Keep 5+ per lane so the marquee never shows a gap.
const REVIEW_LANES = [
  {
    id: 'customers',
    role: 'Customer',
    dir: 'right',
    reviews: [
      { name: 'Ananya Rao', meta: 'Bengaluru', rating: 5, text: 'Booked a haircut at 11am, walked in at 11am. No token, no waiting on a bench, no “sir, please wait five minutes”. This is how it should always have been.' },
      { name: 'Rohit Menon', meta: 'Hyderabad', rating: 5, text: 'The QR check-in is the part I did not expect to love. One scan and I was in the chair. My barber was impressed too.' },
      { name: 'Sneha Kulkarni', meta: 'Pune', rating: 4, text: 'Loved that I could see the real price before confirming. The advance adjusted off my final bill exactly as promised, so nobody made me pay twice.' },
      { name: 'Imran Shaikh', meta: 'Mumbai', rating: 5, text: 'Got an instant WhatsApp confirmation and a reminder an hour before. First salon booking app that did not leave me guessing.' },
      { name: 'Divya Iyer', meta: 'Chennai', rating: 5, text: 'I found a verified salon in under two minutes and booked a colouring slot for the same evening. Weekend evenings are finally not a lottery.' },
      { name: 'Karthik Nair', meta: 'Kochi', rating: 4, text: 'Booked for my parents and they loved it. The address and directions were right there in the app, so we did not lose time looking for the shop.' },
    ],
  },
  {
    id: 'admins',
    role: 'Salon Admin',
    dir: 'left',
    reviews: [
      { name: 'Farhan Qureshi', meta: 'Owner, Velvet Scissors · Bengaluru', rating: 5, text: 'My no-show rate dropped from almost 30 percent to under 5. People who pay an advance and hold a QR code actually turn up.' },
      { name: 'Neha Bansal', meta: 'Owner, The Glow Studio · Delhi', rating: 5, text: 'I run three chairs across two floors. Managing staff schedules, services and payouts from one app replaced a wall of registers and a lot of arguments.' },
      { name: 'Arjun Reddy', meta: 'Owner, Royal Bridal · Hyderabad', rating: 5, text: 'Being listed was free and I was live in four days. On peak wedding season we filled slots that used to stay empty at 3pm on a weekday.' },
      { name: 'Priya Menon', meta: 'Owner, Trim & Co · Kochi', rating: 4, text: 'Wallet credits on every completed booking are a nice touch. Support answered on WhatsApp within minutes, twice.' },
      { name: 'Sameer Joshi', meta: 'Owner, Urban Polish · Pune', rating: 5, text: 'The QR check-in means I know exactly who is in my salon and when. My clients feel looked after and my billing matches the floor exactly.' },
      { name: 'Zoya Ahmed', meta: 'Owner, Aura Beauty Lounge · Mumbai', rating: 5, text: 'I can finally see, slot by slot, which of my stylists is underbooked. I moved clients across teams and revenue followed within a fortnight.' },
    ],
  },
  {
    id: 'providers',
    role: 'Service Provider',
    dir: 'right',
    reviews: [
      { name: 'Vikram Chauhan', meta: 'Senior Stylist · Bengaluru', rating: 5, text: 'My calendar used to be a mess of phone calls. Now a booking just appears on my schedule with the service and the advance already settled.' },
      { name: 'Meera Nair', meta: 'Colour Specialist · Chennai', rating: 5, text: 'I get WhatsApp alerts for each new booking, so I am not chasing confirmations. My day is far calmer than it was.' },
      { name: 'Rahul Verma', meta: 'Barber · Delhi', rating: 4, text: 'Walk-ins still work, but now they sit in the same system as booked slots. I stopped double-booking myself by accident.' },
      { name: 'Sana Fernandes', meta: 'Nail Artist · Mumbai', rating: 5, text: 'My earnings are visible slot by slot and payouts land on time. I stopped keeping a separate notebook for the money side.' },
      { name: 'Karthik Dev', meta: 'Massage Therapist · Hyderabad', rating: 5, text: 'Being able to set my own availability means I take the bookings I actually want. That alone was worth switching over.' },
      { name: 'Ayesha Khan', meta: 'Makeup Artist · Pune', rating: 5, text: 'Bridal clients book weeks ahead and it is all in one place. I know exactly who is coming, when, and what they booked.' },
    ],
  },
];

function Icon({ name, className }: { name: string; className?: string }) {
  const common = {
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 2,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    viewBox: '0 0 24 24',
    className,
    'aria-hidden': true,
  };
  switch (name) {
    case 'search':
      return <svg {...common}><circle cx="11" cy="11" r="7" /><path d="m21 21-4.35-4.35" /></svg>;
    case 'calendar':
      return <svg {...common}><rect x="3" y="4" width="18" height="17" rx="3" /><path d="M16 2v4M8 2v4M3 10h18" /></svg>;
    case 'card':
      return <svg {...common}><rect x="2" y="5" width="20" height="14" rx="3" /><path d="M2 10h20" /></svg>;
    case 'qr':
      return <svg {...common}><rect x="3" y="3" width="7" height="7" rx="1.5" /><rect x="14" y="3" width="7" height="7" rx="1.5" /><rect x="3" y="14" width="7" height="7" rx="1.5" /><path d="M14 14h3v3h-3z" /><path d="M20 14h1M14 20h1M18 18h3v3h-3z" /></svg>;
    case 'smile':
      return <svg {...common}><circle cx="12" cy="12" r="9" /><path d="M8.5 14.5a4.5 4.5 0 0 0 7 0" /><path d="M9 9h.01M15 9h.01" /></svg>;
    case 'shield':
      return <svg {...common}><path d="M12 2.5 4.5 5v5.5c0 4.8 3.3 8.5 7.5 11 4.2-2.5 7.5-6.2 7.5-11V5z" /><path d="m8.6 11.8 2.3 2.3 4.4-4.4" /></svg>;
    case 'lock':
      return <svg {...common}><rect x="4" y="10" width="16" height="11" rx="3" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></svg>;
    case 'chat':
      return <svg {...common}><path d="M21 12a8.6 8.6 0 0 1-8.6 8.6c-1.5 0-2.9-.36-4.1-1L3 21l1.5-4.9a8.6 8.6 0 1 1 16.5-4.1z" /><path d="M8 10h8M8 14h5" /></svg>;
    case 'wallet':
      return <svg {...common}><rect x="3" y="6" width="18" height="14" rx="3" /><path d="M3 10h18" /><path d="M16.5 14.5h.01" /></svg>;
    case 'check-calendar':
      return <svg {...common}><rect x="3" y="4" width="18" height="17" rx="3" /><path d="M16 2v4M8 2v4M3 10h18" /><path d="m9 15 2 2 4-4" /></svg>;
    case 'bag':
      return <svg {...common}><path d="M6 3 3 6v13a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-3z" /><path d="M3 6h18" /><path d="M16 10a4 4 0 0 1-8 0" /></svg>;
    case 'clock':
      return <svg {...common}><rect x="3" y="4" width="18" height="17" rx="3" /><path d="M16 2v4M8 2v4M3 10h18" /><circle cx="12" cy="16" r="2.5" /><path d="M12 14.5V16l1.2 1" /></svg>;
    case 'users':
      return <svg {...common}><circle cx="9" cy="8" r="3.5" /><path d="M2.5 20a6.5 6.5 0 0 1 13 0" /><path d="M16.5 4.5a3.5 3.5 0 0 1 0 7" /><path d="M16.8 13.4a6.5 6.5 0 0 1 4.7 6.6" /></svg>;
    case 'spark':
      return <svg {...common}><path d="m12 2 2.1 6.4L20.5 10l-6.4 1.9L12 18.3l-2.1-6.4L3.5 10l6.4-1.6z" /></svg>;
    case 'arrow':
      return <svg {...common}><path d="M5 12h14" /><path d="m13 6 6 6-6 6" /></svg>;
    case 'check':
      return <svg {...common}><path d="m4.5 12.5 5 5 10-10" /></svg>;
    case 'scissors':
      return <svg {...common}><circle cx="6" cy="6" r="3" /><circle cx="6" cy="18" r="3" /><path d="M8.5 8.2 20.5 20M8.5 15.8 20.5 4" /></svg>;
    case 'comb':
      return <svg {...common}><path d="M5 3v18" /><path d="M5 3h12" /><path d="M5 7h10M5 11h12M5 15h10M5 19h12" /></svg>;
    case 'bell':
      return <svg {...common}><path d="M6 16v-5a6 6 0 0 1 12 0v5l1.5 2.4h-15z" /><path d="M10 20.5a2 2 0 0 0 4 0" /></svg>;
    case 'droplet':
      return <svg {...common}><path d="M12 3s6 6.4 6 11a6 6 0 0 1-12 0c0-4.6 6-11 6-11z" /></svg>;
    case 'brush':
      return <svg {...common}><path d="m14.5 4.5 5 5L11 18l-5-5z" /><path d="M6 13c-2 0-3 1.5-3 3.5S2 20 2 20s4 0 5.5-1.5S9 15 9 15" /></svg>;
    case 'leaf':
      return <svg {...common}><path d="M5 19c0-8 6-14 15-14 0 9-6 15-14 15" /><path d="M5 19 13 11" /></svg>;
    case 'crown':
      return <svg {...common}><path d="m3 8 4 4 5-6 5 6 4-4-2 11H5z" /></svg>;
    case 'palette':
      return <svg {...common}><path d="M12 3a9 9 0 1 0 0 18c1.2 0 2-.8 2-2 0-.6-.3-1-.6-1.4-.3-.4-.4-.8-.4-1.2 0-1 .8-1.4 1.8-1.4H17a4 4 0 0 0 4-4c0-4.4-4-8-9-8z" /><circle cx="7.5" cy="11" r="1" /><circle cx="10" cy="7" r="1" /><circle cx="14.5" cy="7" r="1" /></svg>;
    case 'hand':
      return <svg {...common}><path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V12" /><path d="M11 11V4.5a1.5 1.5 0 0 1 3 0V12" /><path d="M14 11.5V6a1.5 1.5 0 0 1 3 0v8a7 7 0 0 1-7 7h-.5A6.5 6.5 0 0 1 5 17.8L3.5 14a1.5 1.5 0 0 1 2.6-1.4L8 15" /></svg>;
    case 'razor':
      return <svg {...common}><rect x="4" y="3" width="16" height="6" rx="1.5" /><path d="M12 9v12" /><path d="M8 6h8" /></svg>;
    case 'trend':
      return <svg {...common}><path d="M3 17l6-6 4 4 8-8" /><path d="M15 7h6v6" /></svg>;
    default:
      return <svg {...common}><circle cx="12" cy="12" r="9" /></svg>;
  }
}

export default function LandingPage() {
  const [formData, setFormData] = useState({
    salon_name: '',
    owner_name: '',
    phone: '',
    state: '',
    city_id: '',
    sub_area_id: '',
    street_address: '',
    pincode: '',
    message: ''
  });
  const [photo, setPhoto] = useState<File | null>(null);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);
  // Optional: where BookALook should send the salon's settlements. Carried to
  // the salon when it is onboarded; the owner can also add it later in the app.
  const [bank, setBank] = useState<BankDetailsInput>(EMPTY_BANK_DETAILS);
  const [bankErrors, setBankErrors] = useState<Partial<Record<keyof BankDetailsInput, string>>>({});
  const [status, setStatus] = useState<'idle' | 'submitting' | 'success' | 'error'>('idle');
  const [faqFor, setFaqFor] = useState<'customers' | 'owners'>('customers');
  const origin = useOrigin();
  const [errorMessage, setErrorMessage] = useState('');

  // City and area are picked, never typed. Typed cities left this table holding
  // "navi mumbai" and "Pimpri Chinchwad", which no collaborator could be
  // matched against.
  const [cities, setCities] = useState<{ id: string; name: string; state: string }[]>([]);
  const [states, setStates] = useState<string[]>([]);
  const [subAreas, setSubAreas] = useState<{ id: string; name: string }[]>([]);
  const [loadingAreas, setLoadingAreas] = useState(false);

  useEffect(() => {
    fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/cities`, { headers: { Accept: 'application/json' } })
      .then((r) => r.json())
      .then((list) => {
        if (Array.isArray(list)) {
          setCities(list);
          const uniqueStates = Array.from(new Set(list.map((c: any) => c.state).filter(Boolean))) as string[];
          uniqueStates.sort();
          setStates(uniqueStates);
        }
      })
      .catch(() => setCities([]));
  }, []);

  // Areas belong to a city, so the second dropdown refills whenever the first
  // changes — and clears any area already chosen, which would now be in the
  // wrong city.
  useEffect(() => {
    if (!formData.city_id) {
      setSubAreas([]);
      return;
    }

    setLoadingAreas(true);
    fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/cities/${formData.city_id}/sub-areas`, {
      headers: { Accept: 'application/json' },
    })
      .then((r) => r.json())
      .then((d) => setSubAreas(d?.sub_areas ?? []))
      .catch(() => setSubAreas([]))
      .finally(() => setLoadingAreas(false));
  }, [formData.city_id]);

  const handleInputChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>
  ) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value,
      ...(name === 'state' ? { city_id: '', sub_area_id: '' } : {}),
      ...(name === 'city_id' ? { sub_area_id: '' } : {}),
    }));
  };

  const handlePhotoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (!file.type.startsWith('image/')) {
      setErrorMessage('Please select a valid image file (JPEG, PNG, WebP).');
      return;
    }

    if (file.size > 5 * 1024 * 1024) {
      setErrorMessage('The image size cannot exceed 5MB.');
      return;
    }

    setErrorMessage('');
    setPhoto(file);
    const reader = new FileReader();
    reader.onloadend = () => {
      setPhotoPreview(reader.result as string);
    };
    reader.readAsDataURL(file);
  };

  const handleRemovePhoto = () => {
    setPhoto(null);
    setPhotoPreview(null);
  };

  const filteredCities = formData.state 
    ? cities.filter(c => c.state === formData.state) 
    : [];

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (status === 'submitting') return;

    const problems = validateBankDetails(bank);
    setBankErrors(problems);
    if (Object.keys(problems).length > 0) {
      setStatus('error');
      setErrorMessage('Please check the bank details, or leave them all empty.');
      return;
    }

    setStatus('submitting');
    setErrorMessage('');

    try {
      const payload = new FormData();
      payload.append('salon_name', formData.salon_name);
      payload.append('owner_name', formData.owner_name);
      payload.append('phone', formData.phone);
      payload.append('city_id', formData.city_id);
      payload.append('sub_area_id', formData.sub_area_id);
      payload.append('street_address', formData.street_address);
      payload.append('pincode', formData.pincode);
      if (formData.message) {
        payload.append('message', formData.message);
      }
      if (photo) {
        payload.append('photo', photo);
      }
      Object.entries(bankDetailsPayload(bank)).forEach(([key, value]) => {
        if (value) payload.append(key, value);
      });

      const response = await fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/enquiries`, {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
        },
        body: payload,
      });

      if (response.ok) {
        setStatus('success');
        setFormData({ salon_name: '', owner_name: '', phone: '', state: '', city_id: '', sub_area_id: '', street_address: '', pincode: '', message: '' });
        setBank(EMPTY_BANK_DETAILS);
        setBankErrors({});
        setPhoto(null);
        setPhotoPreview(null);
      } else {
        const data = await response.json();
        setStatus('error');
        // Laravel returns a field map; its own wording is more use than a
        // generic failure line.
        const firstError = data?.errors ? Object.values(data.errors)[0] : null;
        if (data?.errors) {
          const fromServer: Partial<Record<keyof BankDetailsInput, string>> = {};
          (Object.keys(EMPTY_BANK_DETAILS) as (keyof BankDetailsInput)[]).forEach((k) => {
            const msg = data.errors[k];
            if (Array.isArray(msg) && msg.length) fromServer[k] = String(msg[0]);
          });
          setBankErrors(fromServer);
        }
        setErrorMessage(
          Array.isArray(firstError)
            ? String(firstError[0])
            : data.message || 'Failed to submit enquiry. Please check your details.'
        );
      }
    } catch (error) {
      setStatus('error');
      setErrorMessage('A network error occurred. Please try again.');
    }
  };

  return (
    <main className={s.page}>
      {/* ============ HERO — for customers ============ */}
      <section id="top" className={s.cHero}>
        <div className={s.cHeroGlow} aria-hidden="true" />
        <div className={s.cHeroGrid} aria-hidden="true" />

        <Parallax speed={0.14} className={s.cHeroLayer}>
          <div className={s.cHeroContent}>
            <p className={s.cHeroEyebrow}><span className={s.cHeroDot} aria-hidden="true" /> Salon booking, minus the waiting</p>
            <h1 className={s.cHeroTitle}>
              Your next <span className={s.cHeroAccent}><RotatingWord words={HERO_WORDS} /></span>,<br />
              booked in a minute.
            </h1>
            <p className={s.cHeroSub}>
              Find a verified salon near you, pick a live free slot and walk straight in with a QR code. No calls. No waiting.
            </p>
            <div className={s.cHeroBadges}>
              <StoreBadge store="google" url={CUSTOMER_PLAY_STORE_URL} label="Google Play" />
              <StoreBadge store="apple" url={CUSTOMER_APP_STORE_URL} label="App Store" />
            </div>
            <ul className={s.cHeroTrust}>
              {HERO_TRUST.map((t) => (
                <li key={t}><Icon name="check" /> {t}</li>
              ))}
            </ul>
          </div>
        </Parallax>

        {/* Services you can book, drifting past in two rows. */}
        <div className={s.cTicker} aria-label="Services you can book on BookALook">
          {TICKER_ROWS.map((row, r) => (
            <div key={r} className={`${s.cLane} ${r % 2 ? s.cLaneReverse : ''}`}>
              {[0, 1].map((copy) => (
                <div key={copy} className={s.cLaneSet} aria-hidden={copy === 1}>
                  {row.map((item) => (
                    <span key={`${copy}-${item.label}`} className={s.cChip}>
                      <span className={s.cChipIcon}><Icon name={item.icon} /></span>
                      {item.label}
                    </span>
                  ))}
                </div>
              ))}
            </div>
          ))}
        </div>

        <div className={s.cHeroFoot}>
          <a className={s.cHeroOwner} href="#for-salons">Own a salon? Grow with BookALook →</a>
          <a className={s.cScroll} href="#better-looks" aria-label="Scroll down">
            Scroll <span aria-hidden="true">⌄</span>
          </a>
        </div>
      </section>

      {/* ============ BETTER LOOKS — floating stickers ============ */}
      <section id="better-looks" className={s.cFloat}>
        {STICKERS.slice(2).map((st, i) => (
          <Parallax key={st.label} speed={[0.3, -0.25, 0.22, -0.32, 0.26, -0.2][i]} rotate={[-1.5, 1.5, -1, 1, -1.5, 1][i]} className={`${s.cFloatItem} ${s[`cFloatItem${i}`]}`}>
            <span className={s.cFloatCircle}>{st.emoji}</span>
          </Parallax>
        ))}
        <Reveal className={s.cFloatText}>
          <h2>Better looks for <em>more people</em></h2>
          <p>
            BookALook helps you find a great salon, see real prices and free slots, and turn up to a chair that is
            ready for you.
          </p>
        </Reveal>
      </section>

      {/* ============ STATS STRIP ============ */}
      <section className={s.cStatsWrap}>
        <div className={s.container}>
          <Reveal variant="zoom" className={s.cStats}>
            {CUSTOMER_STATS.map((st) => (
              <div className={s.cStat} key={st.label}>
                <b><CountUp to={st.to} prefix={st.prefix} suffix={st.suffix} /></b>
                <span>{st.label}</span>
                <i aria-hidden="true">{st.icon}</i>
              </div>
            ))}
          </Reveal>
        </div>
      </section>

      {/* ============ WHAT'S WAITING ON THE APP ============ */}
      <section id="app" className={s.cApp}>
        <div className={`${s.container} ${s.center}`}>
          <Reveal>
            <h2 className={s.cAppTitle}>What’s waiting for you<br />on the app?</h2>
            <p className={s.lead}>Everything you need to book a salon the way you would book a cab.</p>
          </Reveal>
          <div className={s.cAppStage}>
            <div className={s.cAppCol}>
              {APP_FEATURES.slice(0, 4).map((f, i) => (
                <Reveal key={f.title} variant="left" delay={i * 90} className={s.cAppTile}>
                  <span className={s.cAppEmoji}>{f.emoji}</span>
                  <div><b>{f.title}</b><p>{f.desc}</p></div>
                </Reveal>
              ))}
            </div>

            <Parallax speed={-0.08} className={s.cPhoneWrap}>
              <div className={s.cPhone} aria-label="BookALook customer app preview" role="img">
                <div className={s.cPhoneNotch} />
                <div className={s.cPhoneScreen}>
                  <p className={s.cPhoneHello}>Hi Ananya 👋</p>
                  <div className={s.cPhoneSearch}>🔍 Search haircut, facial, spa…</div>
                  <div className={s.cPhoneChips}>
                    <span className={s.on}>Haircut</span><span>Facial</span><span>Nails</span>
                  </div>
                  <div className={s.cPhoneCard}>
                    <small>Your next appointment</small>
                    <b>Glow Studio · Baner</b>
                    <span>Today · 6:30 – 7:15 PM</span>
                    <div><em>Confirmed</em><strong>Show QR</strong></div>
                  </div>
                  <div className={s.cPhoneSalon}><span>💈</span><div><b>Urban Trim</b><small>★ 4.7 · 1.2 km</small></div><i>Book</i></div>
                  <div className={s.cPhoneSalon}><span>🌸</span><div><b>Aura Lounge</b><small>★ 4.8 · 2.0 km</small></div><i>Book</i></div>
                </div>
              </div>
            </Parallax>

            <div className={s.cAppCol}>
              {APP_FEATURES.slice(4).map((f, i) => (
                <Reveal key={f.title} variant="right" delay={i * 90} className={s.cAppTile}>
                  <span className={s.cAppEmoji}>{f.emoji}</span>
                  <div><b>{f.title}</b><p>{f.desc}</p></div>
                </Reveal>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* ============ HOW IT WORKS ============ */}
      <section id="how-it-works" className={s.section}>
        <div className={`${s.container} ${s.center}`}>
          <Reveal>
            <p className={s.kicker}>How it works</p>
            <h2 className={s.title}>Three taps to your next look</h2>
          </Reveal>
          <ol className={s.cSteps}>
            {CUSTOMER_STEPS.map((step, i) => (
              <Reveal as="li" key={step.title} delay={i * 140} className={s.cStep}>
                <span className={s.cStepEmoji}>{step.emoji}</span>
                <small>Step {i + 1}</small>
                <b>{step.title}</b>
                <p>{step.desc}</p>
              </Reveal>
            ))}
          </ol>
        </div>
      </section>

      {/* ============ REVIEWS ============ */}
      <section id="reviews" className="blk-reviews">
        <div className="blk-container">
          <p className="blk-section-kicker">Reviews</p>
          <h2 className="blk-section-title">Loved by customers, trusted by salons</h2>
          <p className="blk-section-sub">What customers, salon owners and stylists say about BookALook.</p>
        </div>
        <div className="blk-reviews__stage">
          {REVIEW_LANES.map((lane, laneIndex) => (
            <div className="blk-reviews__lane" key={lane.id} style={{ animationDelay: `${laneIndex * 0.14}s` }}>
              <div
                className={`blk-reviews__track blk-reviews__track--${lane.dir}`}
                style={{ animationDuration: `${[52, 62, 56][laneIndex]}s`, animationDelay: `${laneIndex * -7}s` }}
              >
                {[0, 1].map((copy) => (
                  <div className="blk-reviews__set" key={copy} aria-hidden={copy === 1}>
                    {lane.reviews.map((review) => (
                      <article className="blk-reviews__card" key={`${copy}-${review.name}`}>
                        <p className="blk-reviews__role">{lane.role}</p>
                        <span className="blk-reviews__stars" role="img" aria-label={`Rated ${review.rating} out of 5`}>
                          <span className="is-on" aria-hidden="true">{'★'.repeat(review.rating)}</span>
                          <span aria-hidden="true">{'★'.repeat(5 - review.rating)}</span>
                        </span>
                        <p className="blk-reviews__text">{review.text}</p>
                        <div className="blk-reviews__by">
                          <span className="blk-reviews__avatar" aria-hidden="true">{review.name.charAt(0)}</span>
                          <span className="blk-reviews__who">
                            <span className="blk-reviews__name">{review.name}</span>
                            <span className="blk-reviews__meta">{review.meta}</span>
                          </span>
                        </div>
                      </article>
                    ))}
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* ============ DOWNLOAD — QR like Zomato ============ */}
      <section id="download" className={s.cDownloadWrap}>
        <div className={s.container}>
          <Reveal variant="zoom" className={s.cDownload}>
            <div className={s.cDownloadText}>
              <h2>Download the app now!</h2>
              <p>Book salons near you in a minute — free on Android and iPhone.</p>
              <div className={s.cHeroBadges}>
                <StoreBadge store="google" url={CUSTOMER_PLAY_STORE_URL} label="Google Play" />
                <StoreBadge store="apple" url={CUSTOMER_APP_STORE_URL} label="App Store" />
              </div>
            </div>
            <Parallax speed={-0.1} className={s.cQrPhone}>
              <div className={s.cQrPhoneScreen}>
                <div className={s.cPhoneNotch} />
                <p>Scan the QR code to<br />download the app</p>
                <QrCode value={`${origin}/download?app=customer`} size={150} label="QR code to download the BookALook app" />
              </div>
            </Parallax>
          </Reveal>
        </div>
      </section>

      {/* ======================================================================
          FOR SALON OWNERS — a little further down
          ====================================================================== */}
      <section id="for-salons" className={s.oBand}>
        {STICKERS.slice(0, 3).map((st, i) => (
          <Parallax key={st.label} speed={[0.25, -0.3, 0.2][i]} rotate={[1, -1, 1][i]} className={`${s.oSticker} ${s[`oSticker${i}`]}`}>
            <span>{st.emoji}</span>
          </Parallax>
        ))}
        <div className={`${s.container} ${s.oBandGrid}`}>
          <Reveal variant="left">
            <p className={s.oKicker}>For salon owners &amp; barbers</p>
            <h2 className={s.oTitle}>Fill every chair.<br /><em>Get paid before they arrive.</em></h2>
            <p className={s.oLead}>
              New customers find you in the app, pay an advance with every booking so they turn up, and you run
              bookings, staff, billing and payouts from one Partner App.
            </p>
            <div className={s.heroCtas}>
              <a className={`${s.btn} ${s.btnPrimary}`} href="#enquiry-section">Register your salon <Icon name="arrow" /></a>
              <a className={`${s.btn} ${s.oBtnGhost}`} href="#pricing">See plans &amp; pricing</a>
            </div>
          </Reveal>
          <Reveal variant="right" className={s.oGainList}>
            {GAINS.map((g) => (
              <div className={s.oGain} key={g.title}>
                <span className={s.oPain}>{g.pain}</span>
                <b>{g.title}</b>
                <p>{g.desc}</p>
              </div>
            ))}
          </Reveal>
        </div>
      </section>

      <section id="features" className={`${s.section} ${s.sectionTint}`}>
        <div className={s.container}>
          <Reveal>
            <p className={s.kicker}>Everything in the Partner App</p>
            <h2 className={s.title}>Built for how a salon actually runs</h2>
          </Reveal>
          <div className={s.featureGrid}>
            {OWNER_FEATURES.map((f, i) => (
              <Reveal as="article" key={f.title} delay={(i % 4) * 80} className={s.feature}>
                <span className={s.featureIcon}><Icon name={f.icon} /></span>
                <h3>{f.title}</h3>
                <p>{f.desc}</p>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <PricingSection />

      <section id="get-started" className={`${s.section} ${s.sectionTint}`}>
        <div className={`${s.container} ${s.startGrid}`}>
          <Reveal variant="left">
            <p className={s.kicker}>Get started</p>
            <h2 className={s.title}>Your salon on BookALook in four steps</h2>
            <ol className={s.steps}>
              {START_STEPS.map((step, i) => (
                <li key={step.title}>
                  <span className={s.stepNum}>{i + 1}</span>
                  <div><b>{step.title}</b><p>{step.desc}</p></div>
                </li>
              ))}
            </ol>
            <div className={s.oQrCard}>
              <QrCode value={`${origin}/download?app=partner`} size={96} label="QR code to download the BookALook Partner app" />
              <div>
                <b>Prefer your phone?</b>
                <p>Scan to get the Partner App and register your salon yourself.</p>
                <div className={s.badges}>
                  <StoreBadge store="google" url={PARTNER_PLAY_STORE_URL} label="Google Play" />
                  <StoreBadge store="apple" url={PARTNER_APP_STORE_URL} label="App Store" />
                </div>
              </div>
            </div>
          </Reveal>

          <div id="enquiry-section" className={`enquiry-section ${s.formWrap}`}>
            <div style={{ maxWidth: '600px', width: '100%', background: 'white', padding: '2rem', borderRadius: '12px', boxShadow: '0 4px 6px rgba(0,0,0,0.05)' }}>
              <h2 style={{ textAlign: 'center', marginBottom: '0.5rem' }}>Partner With Us</h2>
              <p style={{ textAlign: 'center', color: '#666', marginBottom: '2rem' }}>Fill out the form below and our team will get in touch to onboard your salon.</p>
          
              {status === 'success' ? (
                <div style={{ padding: '1rem', backgroundColor: '#e8f5e9', color: '#2e7d32', borderRadius: '8px', textAlign: 'center', fontWeight: 'bold' }}>
                  Thank you! Your enquiry has been submitted successfully. Our team will contact you soon.
                </div>
              ) : (
                <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                  {status === 'error' && (
                    <div style={{ padding: '0.75rem', backgroundColor: '#ffebee', color: '#c62828', borderRadius: '8px', fontSize: '0.9rem' }}>
                      {errorMessage}
                    </div>
                  )}
              
                  <div>
                    <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Salon Name *</label>
                    <input 
                      type="text" 
                      name="salon_name" 
                      required 
                      value={formData.salon_name} 
                      onChange={handleInputChange}
                      style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                    />
                  </div>

                  <div>
                    <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Owner Name *</label>
                    <input 
                      type="text" 
                      name="owner_name" 
                      required 
                      value={formData.owner_name} 
                      onChange={handleInputChange}
                      style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                    />
                  </div>

                  <div>
                    <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Phone Number *</label>
                    <input 
                      type="tel" 
                      name="phone" 
                      required 
                      value={formData.phone} 
                      onChange={handleInputChange}
                      style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                    />
                  </div>

                  <div>
                    <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>State *</label>
                    <select
                      name="state"
                      required
                      value={formData.state}
                      onChange={handleInputChange}
                      style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px', background: 'white' }}
                    >
                      <option value="">Select your state</option>
                      {states.map((s) => (
                        <option key={s} value={s}>{s}</option>
                      ))}
                    </select>
                  </div>

                  <div>
                    <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>City *</label>
                    <select
                      name="city_id"
                      required
                      disabled={!formData.state}
                      value={formData.city_id}
                      onChange={handleInputChange}
                      style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px', background: 'white' }}
                    >
                      <option value="">
                        {!formData.state ? 'Choose a state first' : 'Select your city'}
                      </option>
                      {filteredCities.map((c) => (
                        <option key={c.id} value={c.id}>{c.name}</option>
                      ))}
                    </select>
                  </div>

                  <div>
                    <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Area *</label>
                    <select
                      name="sub_area_id"
                      required
                      disabled={!formData.city_id || loadingAreas}
                      value={formData.sub_area_id}
                      onChange={handleInputChange}
                      style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px', background: 'white' }}
                    >
                      <option value="">
                        {!formData.city_id
                          ? 'Choose a city first'
                          : loadingAreas
                            ? 'Loading areas…'
                            : subAreas.length === 0
                              ? 'No areas listed for this city yet'
                              : 'Select your area'}
                      </option>
                      {subAreas.map((a) => (
                        <option key={a.id} value={a.id}>{a.name}</option>
                      ))}
                    </select>
                    <p style={{ marginTop: '0.4rem', fontSize: '0.8rem', color: '#777' }}>
                      Helps us send someone who already works near you.
                    </p>
                  </div>

                  <div>
                    <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Street Address *</label>
                    <textarea
                      name="street_address"
                      required
                      rows={2}
                      value={formData.street_address}
                      onChange={handleInputChange}
                      style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                    />
                  </div>

                  <div>
                    <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Pincode *</label>
                    <input
                      type="text"
                      name="pincode"
                      required
                      value={formData.pincode}
                      onChange={handleInputChange}
                      style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                    />
                  </div>

                  <div>
                    <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Message (Optional)</label>
                    <textarea 
                      name="message" 
                      rows={3} 
                      value={formData.message} 
                      onChange={handleInputChange}
                      placeholder="Tell us anything else about your salon..."
                      style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                    ></textarea>
                  </div>

                  <div>
                    <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Salon Photo (Optional)</label>
                    {photoPreview ? (
                      <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', padding: '0.75rem', border: '1px solid #ddd', borderRadius: '8px', background: '#fafafa' }}>
                        <img 
                          src={photoPreview} 
                          alt="Salon preview" 
                          style={{ width: '64px', height: '64px', objectFit: 'cover', borderRadius: '6px', border: '1px solid #eee' }} 
                        />
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <p style={{ margin: 0, fontSize: '0.9rem', fontWeight: 500, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                            {photo?.name}
                          </p>
                          <p style={{ margin: 0, fontSize: '0.75rem', color: '#666' }}>
                            {(photo ? (photo.size / (1024 * 1024)).toFixed(2) : 0)} MB
                          </p>
                        </div>
                        <button 
                          type="button" 
                          onClick={handleRemovePhoto}
                          style={{ background: '#ff4d4f', color: '#fff', border: 'none', borderRadius: '6px', padding: '0.4rem 0.75rem', fontSize: '0.8rem', cursor: 'pointer' }}
                        >
                          Remove
                        </button>
                      </div>
                    ) : (
                      <label 
                        style={{ 
                          display: 'flex', 
                          flexDirection: 'column', 
                          alignItems: 'center', 
                          justifyContent: 'center', 
                          padding: '1.25rem', 
                          border: '2px dashed #ccc', 
                          borderRadius: '8px', 
                          cursor: 'pointer', 
                          background: '#fafafa',
                          transition: 'border-color 0.2s',
                        }}
                      >
                        <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#666" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ marginBottom: '0.5rem' }}>
                          <rect width="18" height="18" x="3" y="3" rx="2" ry="2" />
                          <circle cx="9" cy="9" r="2" />
                          <path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21" />
                        </svg>
                        <span style={{ fontSize: '0.9rem', color: '#333', fontWeight: 500 }}>Click to upload a salon photo</span>
                        <span style={{ fontSize: '0.75rem', color: '#888', marginTop: '0.2rem' }}>PNG, JPG, or WebP up to 5MB</span>
                        <input 
                          type="file" 
                          accept="image/png,image/jpeg,image/webp" 
                          onChange={handlePhotoChange} 
                          style={{ display: 'none' }} 
                        />
                      </label>
                    )}
                  </div>

                  <details style={{ border: '1px solid #ddd', borderRadius: '8px', padding: '0.75rem 1rem', background: '#fafafa' }} open={Object.keys(bankErrors).length > 0 || undefined}>
                    <summary style={{ cursor: 'pointer', fontWeight: 600 }}>Bank details for payouts (optional)</summary>
                    <p style={{ margin: '0.5rem 0 0.75rem', fontSize: '0.8rem', color: '#666' }}>
                      BookALook collects advances from your customers and sends your settlements here. You can skip this and add it later in the BookALook Partner app.
                    </p>
                    <div style={{ display: 'grid', gap: '0.75rem' }}>
                      {(Object.keys(EMPTY_BANK_DETAILS) as (keyof BankDetailsInput)[]).map((key) => (
                        <div key={key}>
                          <label htmlFor={key} style={{ display: 'block', marginBottom: '0.35rem', fontWeight: 500, fontSize: '0.9rem' }}>
                            {BANK_FIELD_LABELS[key]}
                          </label>
                          <input
                            id={key}
                            name={key}
                            type="text"
                            inputMode={key === 'bank_account_number' ? 'numeric' : undefined}
                            autoComplete="off"
                            value={bank[key]}
                            onChange={(e) => {
                              const value = e.target.value;
                              setBank((prev) => ({ ...prev, [key]: value }));
                              if (bankErrors[key]) setBankErrors((prev) => ({ ...prev, [key]: undefined }));
                            }}
                            placeholder={key === 'bank_ifsc' ? 'e.g. HDFC0001234' : key === 'bank_upi_id' ? 'e.g. name@okhdfcbank' : undefined}
                            aria-invalid={Boolean(bankErrors[key])}
                            style={{ width: '100%', padding: '0.65rem', border: `1px solid ${bankErrors[key] ? '#c62828' : '#ccc'}`, borderRadius: '8px', textTransform: key === 'bank_ifsc' ? 'uppercase' : undefined }}
                          />
                          {bankErrors[key] && (
                            <p style={{ margin: '0.3rem 0 0', fontSize: '0.78rem', color: '#c62828' }}>{bankErrors[key]}</p>
                          )}
                        </div>
                      ))}
                    </div>
                  </details>

                  <button 
                    type="submit" 
                    disabled={status === 'submitting'}
                    style={{ 
                      padding: '1rem', 
                      backgroundColor: status === 'submitting' ? '#9c27b088' : '#9c27b0', 
                      color: 'white', 
                      border: 'none', 
                      borderRadius: '8px', 
                      fontWeight: 'bold',
                      fontSize: '1rem',
                      cursor: status === 'submitting' ? 'not-allowed' : 'pointer',
                      marginTop: '1rem'
                    }}
                  >
                    {status === 'submitting' ? 'Submitting...' : 'Submit Enquiry'}
                  </button>
                </form>
              )}
            </div>
          </div>
        </div>
      </section>

      <section className={s.section}>
        <div className={`${s.container} ${s.center}`}>
          <Reveal>
            <p className={s.kicker}>One app for the whole team</p>
            <h2 className={s.title}>You, your stylists, and us — in the same app</h2>
          </Reveal>
          <div className={s.roleGrid} style={{ textAlign: 'left' }}>
            {SALON_ROLES.map((r, i) => (
              <Reveal as="article" key={r.tag} delay={i * 110} className={s.role}>
                <small>{r.tag}</small>
                <h3>{r.title}</h3>
                <p>{r.desc}</p>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* ============ FAQ ============ */}
      <section id="faq" className={`${s.section} ${s.sectionTint}`}>
        <div className={`${s.container} ${s.center}`}>
          <Reveal>
            <p className={s.kicker}>FAQ</p>
            <h2 className={s.title}>Questions, answered</h2>
          </Reveal>
          <div className={s.faqTabs} role="tablist" aria-label="Questions for">
            {(['customers', 'owners'] as const).map((who) => (
              <button
                key={who}
                type="button"
                role="tab"
                aria-selected={faqFor === who}
                className={`${s.faqTab} ${faqFor === who ? s.faqTabOn : ''}`}
                onClick={() => setFaqFor(who)}
              >
                {who === 'customers' ? 'For customers' : 'For salon owners'}
              </button>
            ))}
          </div>
          <div className={s.faqList} style={{ textAlign: 'left' }}>
            {(faqFor === 'customers' ? CUSTOMER_FAQ : FAQ_ITEMS).map((item) => (
              <details className={s.faqItem} key={item.q}>
                <summary>{item.q}</summary>
                <p>{item.a}</p>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* ============ CLOSING ============ */}
      <section className={`${s.closing} ${s.closingTop}`}>
        <div className={s.container}>
          <Reveal variant="zoom" className={s.closingCard}>
            <div>
              <h2>Your chair is waiting.</h2>
              <p>Get the app and book your next salon visit in a minute.</p>
            </div>
            <div className={s.closingActions}>
              <a className={s.btn} href="#download">Get the app</a>
              <a className={`${s.btn} ${s.closingGhost}`} href="#for-salons">I own a salon</a>
            </div>
          </Reveal>
        </div>
      </section>
    </main>
  );
}
