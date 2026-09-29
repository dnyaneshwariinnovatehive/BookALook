/**
 * Emits `legal_documents.dart` for the Customer and Partner apps from the
 * website's `src/lib/legal.ts`.
 *
 * The website is the single source of truth for approved legal wording. That
 * only stays true if the copy in the apps is generated rather than retyped —
 * a hand-copied duplicate is a fourth version of every policy that nobody
 * remembers to update.
 *
 * Run from `website/`:
 *   node --experimental-strip-types scripts/generate-legal-dart.mts
 *
 * It writes to both apps. They take the same file because the two apps share a
 * theme, and the partner set is a superset of the customer set — one document
 * list means the viewer screen is identical in both.
 */

import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, '..', '..');
const libDir = join(here, '..', 'src', 'lib');

/**
 * `legal.ts` imports `./site-links` with no extension, because Next resolves it
 * that way. Node's ESM resolver will not, and rewriting `legal.ts` to suit a
 * build script would be the tail wagging the dog — so the two files are staged
 * into a temp directory with the import spelled out, and the real sources are
 * left exactly as the app builds them.
 */
async function loadLegalSource() {
  const stage = mkdtempSync(join(tmpdir(), 'bookalook-legal-'));
  try {
    for (const file of ['legal.ts', 'site-links.ts']) {
      const patched = readFileSync(join(libDir, file), 'utf8').replace(/from '\.\/(site-links)'/, "from './site-links.ts'");
      writeFileSync(join(stage, file), patched, 'utf8');
    }
    return await import(pathToFileURL(join(stage, 'legal.ts')).href);
  } finally {
    // import() has already resolved by the time we get here.
    setTimeout(() => rmSync(stage, { recursive: true, force: true }), 0);
  }
}

const { ABOUT, CANCELLATION_REFUND_POLICY, PARTNER_TERMS, PRIVACY_POLICY, TERMS_OF_USE } = await loadLegalSource();
const { CONTACT_ADDRESS, CONTACT_COMPANY, CONTACT_EMAIL } = await import(pathToFileURL(join(libDir, 'site-links.ts')).href);

/** Shapes of the data read out of src/lib/legal.ts. The import is dynamic, so
 *  TypeScript gets no help from the source and these stand in for it. Mirrors
 *  LegalBlock / LegalSection / LegalDocument in the generated Dart. */
type SourceBlock = { lead?: string; text?: string; bullets?: string[] };
type SourceSection = { heading: string; blocks: SourceBlock[] };
type SourceDoc = {
  slug: string;
  title: string;
  kicker: string;
  summary: string;
  related?: { label: string }[];
  sections: SourceSection[];
};

/** Dart string literal. Everything legal is plain prose, so no escapes come up
 *  in practice, but `$` is escaped because Dart interpolates it. */
function dq(value: string): string {
  return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\$/g, '\\$')}"`;
}

function renderBlocks(blocks: SourceBlock[], indent: number): string {
  const pad = ' '.repeat(indent);
  return blocks
    .map((block: SourceBlock) => {
      const parts: string[] = [];
      if (block.lead) parts.push(`lead: ${dq(block.lead)}`);
      if (block.text) parts.push(`text: ${dq(block.text)}`);
      if (block.bullets) {
        parts.push(`bullets: [\n${block.bullets.map((b: string) => `${pad}    ${dq(b)}`).join(',\n')},\n${pad}  ]`);
      }
      return `${pad}  LegalBlock(${parts.join(', ')}),`;
    })
    .join('\n');
}

function renderDoc(doc: SourceDoc): string {
  return `  LegalDocument(
    slug: ${dq(doc.slug)},
    title: ${dq(doc.title)},
    kicker: ${dq(doc.kicker)},
    summary: ${dq(doc.summary)},
    related: ${dq((doc.related ?? []).map((r: { label: string }) => r.label).join(' · '))},
    sections: [
${doc.sections
  .map(
    (s: SourceSection) => `      LegalSection(
        heading: ${dq(s.heading)},
        blocks: [
${renderBlocks(s.blocks, 8)}
        ],
      ),`
  )
  .join('\n')}
    ],
  ),`;
}

const dart = `// GENERATED FILE — DO NOT EDIT BY HAND.
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
const String kLegalContactCompany = ${dq(CONTACT_COMPANY)};
const String kLegalContactEmail = ${dq(CONTACT_EMAIL)};
const String kLegalContactAddress = ${dq(CONTACT_ADDRESS)};

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
${[TERMS_OF_USE, PRIVACY_POLICY, CANCELLATION_REFUND_POLICY, PARTNER_TERMS, ABOUT].map(renderDoc).join('\n')}
];

/// Look a document up by [slug]. Returns null for an unknown slug so a bad
/// route degrades to an empty screen rather than throwing on a user.
LegalDocument? legalDocumentBySlug(String slug) {
  for (final doc in kLegalDocuments) {
    if (doc.slug == slug) return doc;
  }
  return null;
}
`;

for (const app of ['Customer App', 'Partner App']) {
  const out = join(repoRoot, app, 'lib', 'legal', 'legal_documents.dart');
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, dart, 'utf8');
  console.log(`wrote ${out}`);
}
