import { IsOptional, IsString, MaxLength } from 'class-validator';

export class SearchNotesDto {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  search?: string;
}
