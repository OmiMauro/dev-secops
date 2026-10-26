import { Note } from '../entities/note.entity';

/**
 * Vista: lo que el cliente ve de una nota.
 * Separarla de la entidad permite cambiar la base de datos sin romper
 * la API, y evita filtrar campos internos (como owner con sus datos).
 */
export class NoteResponseDto {
  id: string;
  title: string;
  content: string;
  createdAt: Date;
  updatedAt: Date;

  static fromEntity(note: Note): NoteResponseDto {
    return {
      id: note.id,
      title: note.title,
      content: note.content,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
    };
  }
}
