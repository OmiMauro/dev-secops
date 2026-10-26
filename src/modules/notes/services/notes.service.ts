import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { FindOptionsWhere, ILike, Repository } from 'typeorm';
import { CreateNoteDto } from '../dto/create-note.dto';
import { UpdateNoteDto } from '../dto/update-note.dto';
import { Note } from '../entities/note.entity';

/**
 * Business logic for notes.
 * Every operation receives the userId: a user can only see and modify
 * THEIR notes (prevents IDOR, one of the most common flaws).
 */
@Injectable()
export class NotesService {
  constructor(
    @InjectRepository(Note)
    private readonly notesRepository: Repository<Note>,
  ) {}

  findAllForUser(userId: string, search?: string): Promise<Note[]> {
    const where: FindOptionsWhere<Note> = { ownerId: userId };
    if (search) {
      // TypeORM sends "search" as a bound parameter, it is never
      // concatenated into the SQL. That is why this is not injectable.
      where.title = ILike(`%${search}%`);
    }
    return this.notesRepository.find({
      where,
      order: { updatedAt: 'DESC' },
    });
  }

  async findOneForUser(id: string, userId: string): Promise<Note> {
    const note = await this.notesRepository.findOne({
      where: { id, ownerId: userId },
    });
    // 404 both when it does not exist and when it belongs to someone
    // else: we do not reveal that the note exists.
    if (!note) {
      throw new NotFoundException('Note not found');
    }
    return note;
  }

  create(dto: CreateNoteDto, userId: string): Promise<Note> {
    const note = this.notesRepository.create({ ...dto, ownerId: userId });
    return this.notesRepository.save(note);
  }

  async update(id: string, dto: UpdateNoteDto, userId: string): Promise<Note> {
    const note = await this.findOneForUser(id, userId);
    Object.assign(note, dto);
    return this.notesRepository.save(note);
  }

  async remove(id: string, userId: string): Promise<void> {
    const note = await this.findOneForUser(id, userId);
    await this.notesRepository.remove(note);
  }
}
