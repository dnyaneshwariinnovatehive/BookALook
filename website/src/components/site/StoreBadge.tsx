/**
 * The store badge used by both the site footer and the landing page download
 * sections. The SVGs are inline rather than files so the badge inherits
 * `currentColor` and needs no icon font.
 */
export default function StoreBadge({
  store,
  url,
  label,
}: {
  store: 'apple' | 'google';
  url: string;
  label: string;
}) {
  return (
    <a className="blk-badge" href={url} target="_blank" rel="noopener noreferrer" aria-label={`Download on ${label}`}>
      {store === 'apple' ? (
        <svg className="blk-badge__icon" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M16.365 1.43c0 1.14-.493 2.27-1.177 3.08-.744.9-1.99 1.57-2.987 1.57-.12 0-.23-.01-.33-.02-.124-.85.357-2.02 1.09-2.82.727-.79 1.96-1.45 2.96-1.41.09.2.138.4.138.6z" />
          <path d="M21 16.05c-.26.66-.38.96-.72 1.55-.47.82-1.13 1.85-1.95 1.85-.75 0-1.04-.47-2.16-.46-.91 0-1.34.47-2.15.47-.82 0-1.45-.96-1.93-1.78-1.03-1.79-1.83-5.05-.7-7.26.5-1 1.3-1.58 2.2-1.58.8 0 1.5.47 2.25.47.44 0 .71-.09 1.09-.28 1.15-.59 2.3-2.03 2.47-2.03.09 0 .05.04-.1.32-.6.9-1.03 1.7-1.16 2.6-.18 1.25.5 2.5 1.89 3.43-.15.34-.31.66-.48.96z" />
        </svg>
      ) : (
        <svg className="blk-badge__icon" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M3 20.5v-17c0-.59.34-1.11.84-1.35L13.69 12l-9.85 9.85c-.5-.25-.84-.76-.84-1.35zm13.81-5.38L6.05 21.34l8.49-8.49 2.27 2.27zm3.35-4.31c.34.27.59.68.59 1.19s-.22.9-.57 1.18l-2.29 1.32-2.5-2.5 2.5-2.5 2.27 1.31zM6.05 2.66l10.76 6.22-2.27 2.27-8.49-8.49z" />
        </svg>
      )}
      <span className="blk-badge__text">
        <span className="blk-badge__small">Download on the</span>
        <span className="blk-badge__name">{label}</span>
      </span>
    </a>
  );
}
