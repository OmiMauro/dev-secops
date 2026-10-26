import { Note } from '../entities/note.entity';

/**
 * View: what the client sees of a note.
 * Keeping it separate from the entity lets the database change without
 * breaking the API, and avoids leaking internal fields (like owner).
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
