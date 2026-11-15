/* ============================================================================
   Reviews — the existing section, kept exactly as it was designed.

   Same markup, same `blk-reviews` classes in globals.css, same three drifting
   lanes and hover lift. It only moved out of the page file. The one change to
   the data: three sample reviews that talked about paying an advance were
   dropped, because the site no longer mentions advance payments. Each lane
   still has five, which is the minimum that keeps the marquee gap-free.
   ============================================================================ */

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
      { name: 'Meera Nair', meta: 'Colour Specialist · Chennai', rating: 5, text: 'I get WhatsApp alerts for each new booking, so I am not chasing confirmations. My day is far calmer than it was.' },
      { name: 'Rahul Verma', meta: 'Barber · Delhi', rating: 4, text: 'Walk-ins still work, but now they sit in the same system as booked slots. I stopped double-booking myself by accident.' },
      { name: 'Sana Fernandes', meta: 'Nail Artist · Mumbai', rating: 5, text: 'My earnings are visible slot by slot and payouts land on time. I stopped keeping a separate notebook for the money side.' },
      { name: 'Karthik Dev', meta: 'Massage Therapist · Hyderabad', rating: 5, text: 'Being able to set my own availability means I take the bookings I actually want. That alone was worth switching over.' },
      { name: 'Ayesha Khan', meta: 'Makeup Artist · Pune', rating: 5, text: 'Bridal clients book weeks ahead and it is all in one place. I know exactly who is coming, when, and what they booked.' },
    ],
  },
];

export default function Reviews() {
  return (
    <section id="reviews" className="blk-reviews" style={{ scrollMarginTop: 80 }}>
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
  );
}
