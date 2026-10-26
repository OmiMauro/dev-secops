import { IsOptional, IsString, MaxLength } from 'class-validator';
import { NoNullBytes } from '../../../common/validators/no-null-bytes.decorator';

export class SearchNotesDto {
  @IsOptional()
  @IsString()
  @NoNullBytes()
  @MaxLength(100)
  search?: string;
}
