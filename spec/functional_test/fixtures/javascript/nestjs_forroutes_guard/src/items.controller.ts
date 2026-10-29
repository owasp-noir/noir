import { Controller, Get, Post } from '@nestjs/common';

@Controller('items')
export class ItemsController {
  @Get()
  list() { return []; }

  @Post()
  create() { return {}; }
}
