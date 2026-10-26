import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

/** Todos los campos opcionales: solo se cambia lo que se envía. */
export class UpdateNoteDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  title?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10_000)
  content?: string;
}
