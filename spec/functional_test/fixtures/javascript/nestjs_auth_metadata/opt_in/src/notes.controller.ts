import { Controller, Get, Post } from '@nestjs/common';
import { Secured } from './session-auth.guard';

@Controller('notes')
export class NotesController {
  @Get()
  list() {}

  @Post()
  @Secured()
  create() {}
}
