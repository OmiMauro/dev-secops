import {
  Column,
  CreateDateColumn,
  Entity,
  OneToMany,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { Note } from '../../notes/entities/note.entity';

/** Modelo: cómo se guarda un usuario en la base de datos. */
@Entity('users')
export class User {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  email: string;

  // select: false → nunca se carga salvo que se pida explícitamente.
  // Así es imposible devolver el hash por accidente en una respuesta.
  @Column({ select: false })
  passwordHash: string;

  @OneToMany(() => Note, (note) => note.owner)
  notes: Note[];

  @CreateDateColumn()
  createdAt: Date;
}
