import { NotFoundException } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Note } from '../entities/note.entity';
import { NotesService } from './notes.service';

describe('NotesService', () => {
  let service: NotesService;
  // Repositorio falso: probamos la lógica sin base de datos real.
  const repository = {
    findOne: jest.fn(),
    find: jest.fn(),
    create: jest.fn(),
    save: jest.fn(),
    remove: jest.fn(),
  };

  beforeEach(async () => {
    jest.resetAllMocks();
    const moduleRef = await Test.createTestingModule({
      providers: [
        NotesService,
        { provide: getRepositoryToken(Note), useValue: repository },
      ],
    }).compile();
    service = moduleRef.get(NotesService);
  });

  it('busca la nota filtrando siempre por el dueño', async () => {
    repository.findOne.mockResolvedValue({ id: 'n1', ownerId: 'u1' });

    await service.findOneForUser('n1', 'u1');

    expect(repository.findOne).toHaveBeenCalledWith({
      where: { id: 'n1', ownerId: 'u1' },
    });
  });

  it('lanza 404 si la nota es de otro usuario', async () => {
    repository.findOne.mockResolvedValue(null);

    await expect(service.findOneForUser('n1', 'otro')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('asigna el dueño desde el token, no desde el body', async () => {
    repository.create.mockImplementation((data) => data);
    repository.save.mockImplementation(async (data) => data);

    const note = await service.create({ title: 'Hola' }, 'u1');

    expect(note.ownerId).toBe('u1');
  });
});
