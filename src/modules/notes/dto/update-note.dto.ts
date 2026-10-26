import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { NoNullBytes } from '../../../common/validators/no-null-bytes.decorator';

/** All fields optional: only what is sent gets changed. */
export class UpdateNoteDto {
  @IsOptional()
  @IsString()
  @NoNullBytes()
  @MinLength(1)
  @MaxLength(200)
  title?: string;

  @IsOptional()
  @IsString()
  @NoNullBytes()
  @MaxLength(10_000)
  content?: string;
}
