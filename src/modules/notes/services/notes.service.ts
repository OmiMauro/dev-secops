import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { FindOptionsWhere, ILike, Repository } from 'typeorm';
import { CreateNoteDto } from '../dto/create-note.dto';
import { UpdateNoteDto } from '../dto/update-note.dto';
import { Note } from '../entities/note.entity';

/**
 * Lógica de negocio de las notas.
 * Todas las operaciones reciben el userId: un usuario solo puede
 * ver y tocar SUS notas (evita IDOR, uno de los fallos más comunes).
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
      // TypeORM pasa "search" como parámetro, nunca lo concatena
      // en el SQL. Por eso esto no es vulnerable a SQL injection.
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
    // 404 tanto si no existe como si es de otro usuario:
    // no revelamos que la nota existe.
    if (!note) {
      throw new NotFoundException('Nota no encontrada');
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
