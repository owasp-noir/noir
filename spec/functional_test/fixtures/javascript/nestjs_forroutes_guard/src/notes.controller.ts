import { Controller, Get, Post } from '@nestjs/common';

@Controller('notes')
export class NotesController {
  @Get()
  list() { return []; }

  @Post()
  create() { return {}; }
}
