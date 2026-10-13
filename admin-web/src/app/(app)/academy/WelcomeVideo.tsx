'use client';
import { useRef, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { openLesson, saveProgress } from './actions';

// Mario 2026-10-13: the welcome video is pinned at the top of Academy on EVERY visit (it no longer hides once seen), full width,
// with sound on the learner's tap. Playing it to the end still records the welcome lesson as seen (when that lesson is published).
export function WelcomeVideo({ lessonId, src, poster }: { lessonId?: string; src: string; poster?: string }) {
  const [, start] = useTransition();
  const opened = useRef(false);
  const router = useRouter();
  return (
    <section className="flex flex-col gap-3 rounded-3xl border border-line bg-surface p-3" data-testid="academy-welcome">
      <video src={src} poster={poster} controls playsInline preload="metadata" className="aspect-[9/16] w-full rounded-2xl bg-ink object-cover"
        onPlay={() => { if (lessonId && !opened.current) { opened.current = true; start(() => { void openLesson(lessonId); }); } }}
        onEnded={() => { if (lessonId) start(async () => { await openLesson(lessonId); await saveProgress(lessonId, 1, true); router.refresh(); }); }} />
    </section>
  );
}
