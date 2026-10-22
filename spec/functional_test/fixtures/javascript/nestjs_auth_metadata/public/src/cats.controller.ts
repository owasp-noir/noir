import { Controller, Get, Post } from '@nestjs/common';
import { OpenToGuests, Public } from './public.decorator';

@Controller('cats')
export class CatsController {
  @Public()
  @Get()
  findAll() {}

  @OpenToGuests()
  @Get('random')
  random() {}

  @Post()
  create() {}
}
