import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'CadPilot Admin',
  description: 'CadPilot super-admin operations dashboard',
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
