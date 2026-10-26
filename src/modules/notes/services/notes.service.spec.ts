import { NotFoundException } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { Note } from '../entities/note.entity';
import { NotesService } from './notes.service';

describe('NotesService', () => {
  let service: NotesService;
  // Fake repository: tests the logic without a real database.
  const repository = {
    findOne: vi.fn(),
    find: vi.fn(),
    create: vi.fn(),
    save: vi.fn(),
    remove: vi.fn(),
  };

  beforeEach(async () => {
    const moduleRef = await Test.createTestingModule({
      providers: [
        NotesService,
        { provide: getRepositoryToken(Note), useValue: repository },
      ],
    }).compile();
    service = moduleRef.get(NotesService);
  });

  it('always filters by owner when looking up a note', async () => {
    repository.findOne.mockResolvedValue({ id: 'n1', ownerId: 'u1' });

    await service.findOneForUser('n1', 'u1');

    expect(repository.findOne).toHaveBeenCalledWith({
      where: { id: 'n1', ownerId: 'u1' },
    });
  });

  it('throws 404 when the note belongs to another user', async () => {
    repository.findOne.mockResolvedValue(null);

    await expect(service.findOneForUser('n1', 'otro')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('takes the owner from the token, not from the body', async () => {
    repository.create.mockImplementation((data) => data);
    repository.save.mockImplementation(async (data) => data);

    const note = await service.create({ title: 'Hello' }, 'u1');

    expect(note.ownerId).toBe('u1');
  });
});
