import type { Metadata, Viewport } from 'next';
import { Cormorant_Garamond, Inter } from 'next/font/google';
import './globals.css';
import { StagingBanner } from '@/components/StagingBanner';

const inter = Inter({ subsets: ['latin'], variable: '--font-inter' });
const cormorant = Cormorant_Garamond({ subsets: ['latin'], weight: ['500', '600'], variable: '--font-cormorant' });

export const metadata: Metadata = {
  title: 'Fuxia 360 by HiloLabs.ai',
  description: 'Fuxia 360 by HiloLabs.ai — productos e inventario de Fuxia Ballerinas',
};

export const viewport: Viewport = { themeColor: '#f6f2ec', width: 'device-width', initialScale: 1 };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  const staging = process.env.NEXT_PUBLIC_F360_ENV === 'staging';
  return (
    <html lang="es-MX" className={`${inter.variable} ${cormorant.variable}`}>
      <body className={`min-h-dvh ${staging ? 'pt-12' : ''}`}>
        {staging && <StagingBanner />}
        {children}
      </body>
    </html>
  );
}
