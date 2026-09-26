import type { Metadata, Viewport } from "next";
import ThemeScope from "@/components/ThemeScope";
import { THEME_SCRIPT } from "@/lib/theme-script";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "BookALook — No waiting. Just booking.",
    template: "%s · BookALook",
  },
  description: "Discover salons near you, book in seconds and skip the wait. BookALook is the salon marketplace for customers and salon partners.",
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#F6F5FA" },
    { media: "(prefers-color-scheme: dark)", color: "#0E0C14" },
  ],
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        {/* Sets `.dark` before first paint so a reload never flashes the wrong theme. */}
        <script dangerouslySetInnerHTML={{ __html: THEME_SCRIPT }} />
      </head>
      <body>
        <ThemeScope />
        {children}
      </body>
    </html>
  );
}
