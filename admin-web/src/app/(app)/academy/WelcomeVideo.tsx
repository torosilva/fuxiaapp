'use client';
import { useRef, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { openLesson, saveProgress } from './actions';

// First entry: the welcome video, full width, with sound on the learner's tap. It counts as seen only when it plays to the end
// (saved in the database, so it does not repeat on another phone). "Ver después" only hides it for now.
export function WelcomeVideo({ lessonId, src, poster }: { lessonId: string; src: string; poster?: string }) {
  const [hidden, setHidden] = useState(false);
  const [, start] = useTransition();
  const opened = useRef(false);
  const router = useRouter();
  if (hidden) return null;
  return (
    <section className="flex flex-col gap-3 rounded-3xl border border-line bg-surface p-3" data-testid="academy-welcome">
      <video src={src} poster={poster} controls playsInline preload="metadata" className="aspect-[9/16] w-full rounded-2xl bg-ink object-cover"
        onPlay={() => { if (!opened.current) { opened.current = true; start(() => { void openLesson(lessonId); }); } }}
        onEnded={() => start(async () => { await openLesson(lessonId); await saveProgress(lessonId, 1, true); router.refresh(); })} />
      <button onClick={() => setHidden(true)} className="text-sm text-muted underline-offset-4 hover:underline">Ver después</button>
    </section>
  );
}
