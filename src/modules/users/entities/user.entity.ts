import {
  Column,
  CreateDateColumn,
  Entity,
  OneToMany,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { Note } from '../../notes/entities/note.entity';

/** Model: how a user is stored in the database. */
@Entity('users')
export class User {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  email: string;

  // select: false → never loaded unless explicitly requested.
  // This makes it impossible to leak the hash in a response by accident.
  @Column({ select: false })
  passwordHash: string;

  @OneToMany(() => Note, (note) => note.owner)
  notes: Note[];

  @CreateDateColumn()
  createdAt: Date;
}
