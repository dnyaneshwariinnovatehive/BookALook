import Link from 'next/link';
import type { LegalDocument } from '@/lib/legal';

/**
 * Renders one document from `src/lib/legal.ts`.
 *
 * Every legal page is a thin wrapper around this: a `metadata` export, then
 * `<LegalDocument doc={...} />`. Nothing page-specific, so a policy edit never
 * means touching five components.
 *
 * The table of contents is not decoration. A reader who came here to cancel an
 * appointment should be able to see that section C exists without scrolling
 * past fifteen sections of liability language first.
 */

/** "A. Introduction" -> "a-introduction", "17. Contact" -> "17-contact". */
function anchorFor(heading: string) {
  return heading
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .trim()
    .replace(/\s+/g, '-');
}

export default function LegalDocumentView({ doc }: { doc: LegalDocument }) {
  // A document listing itself as a related link is just a link to where you
  // already are.
  const related = (doc.related ?? []).filter((r) => r.href !== `/${doc.slug}`);

  return (
    <main className="blk-page">
      <div className="blk-container">
        <p className="blk-section-kicker">{doc.kicker}</p>
        <h1 className="blk-section-title">{doc.title}</h1>
        <p className="blk-page__standfirst">{doc.summary}</p>

        <div className="blk-page__body">
          {doc.sections.length > 4 && (
            <nav className="blk-page__toc" aria-label="Contents">
              <p className="blk-page__toc-title">On this page</p>
              <ol className="blk-page__toc-list">
                {doc.sections.map((section) => (
                  <li key={section.heading}>
                    <a href={`#${anchorFor(section.heading)}`}>{section.heading}</a>
                  </li>
                ))}
              </ol>
            </nav>
          )}

          {doc.sections.map((section) => (
            <section key={section.heading} className="blk-page__section" id={anchorFor(section.heading)}>
              <h2 className="blk-page__section-title">{section.heading}</h2>
              {section.blocks.map((block, i) => (
                <div key={i}>
                  {block.lead && <p className="blk-page__lead">{block.lead}</p>}
                  {block.text && <p>{block.text}</p>}
                  {block.bullets && (
                    <ul className="blk-page__bullets">
                      {block.bullets.map((bullet) => (
                        <li key={bullet}>{bullet}</li>
                      ))}
                    </ul>
                  )}
                </div>
              ))}
            </section>
          ))}

          {related.length > 0 && (
            <nav className="blk-page__related" aria-label="Related documents">
              <p className="blk-page__toc-title">Related documents</p>
              <ul className="blk-page__related-list">
                {related.map((link) => (
                  <li key={link.href}>
                    <Link href={link.href}>{link.label}</Link>
                  </li>
                ))}
              </ul>
            </nav>
          )}

          <Link className="blk-page__back" href="/">
            ← Back to BooKalook
          </Link>
        </div>
      </div>
    </main>
  );
}
