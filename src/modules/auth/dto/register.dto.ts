import { IsEmail, IsString, MaxLength, MinLength } from 'class-validator';

export class RegisterDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(12)
  @MaxLength(72) // bcrypt ignores anything beyond 72 bytes
  password: string;
}
