import { notFound } from 'next/navigation';
import { academyLesson } from '@/lib/academy';
import { LessonPlayer } from './LessonPlayer';

export default async function Clase({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const v = await academyLesson(id);
  if (!v.ok) notFound();
  return <LessonPlayer view={v} />;
}
