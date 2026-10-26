import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth } from '@nestjs/swagger';
import { CurrentUser } from '../../auth/decorators/current-user.decorator';
import { AuthUser, JwtAuthGuard } from '../../auth/guards/jwt-auth.guard';
import { CreateNoteDto } from '../dto/create-note.dto';
import { NoteResponseDto } from '../dto/note-response.dto';
import { SearchNotesDto } from '../dto/search-notes.dto';
import { UpdateNoteDto } from '../dto/update-note.dto';
import { NotesService } from '../services/notes.service';

/**
 * Controller: receives the HTTP request, delegates to the service
 * and maps the result to the view (NoteResponseDto).
 * Contains no business logic.
 */
@Controller('notes')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class NotesController {
  constructor(private readonly notesService: NotesService) {}

  @Get()
  async findAll(
    @CurrentUser() user: AuthUser,
    @Query() query: SearchNotesDto,
  ): Promise<NoteResponseDto[]> {
    const notes = await this.notesService.findAllForUser(user.id, query.search);
    return notes.map(NoteResponseDto.fromEntity);
  }

  @Get(':id')
  async findOne(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<NoteResponseDto> {
    const note = await this.notesService.findOneForUser(id, user.id);
    return NoteResponseDto.fromEntity(note);
  }

  @Post()
  async create(
    @CurrentUser() user: AuthUser,
    @Body() dto: CreateNoteDto,
  ): Promise<NoteResponseDto> {
    const note = await this.notesService.create(dto, user.id);
    return NoteResponseDto.fromEntity(note);
  }

  @Patch(':id')
  async update(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateNoteDto,
  ): Promise<NoteResponseDto> {
    const note = await this.notesService.update(id, dto, user.id);
    return NoteResponseDto.fromEntity(note);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<void> {
    return this.notesService.remove(id, user.id);
  }
}
