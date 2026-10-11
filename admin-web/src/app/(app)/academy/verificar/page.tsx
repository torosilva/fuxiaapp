import { BoardMfa } from '../../estrategia/BoardMfa';

// Approving Academy content needs a second factor (aal2, checked in the database by the approval registry).
export default function AcademyMfa() {
  return <BoardMfa area="Academy · aprobar contenido" next="/academy/admin" />;
}
