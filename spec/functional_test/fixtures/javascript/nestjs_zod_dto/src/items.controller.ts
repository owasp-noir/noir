import { Controller, Get, Post, Put, Body, Query } from '@nestjs/common';
import { ItemCreateDto, ItemSearchDto, ItemClassDto } from './items.dto';
@Controller('items')
export class ItemsController {
  @Post()
  create(@Body() dto: ItemCreateDto) { return dto; }
  @Get()
  search(@Query() dto: ItemSearchDto) { return dto; }
  @Put()
  control(@Body() dto: ItemClassDto) { return dto; }
}
