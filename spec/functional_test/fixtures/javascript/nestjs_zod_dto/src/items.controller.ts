import { Controller, Get, Post, Put, Body, Query } from '@nestjs/common';
import { ItemCreateDto, ItemSearchDto, ItemClassDto, PublishedDto, FilterDto, DynamicDto, ExtraDto } from './items.dto';
@Controller('items')
export class ItemsController {
  @Post()
  create(@Body() dto: ItemCreateDto) { return dto; }
  @Get()
  search(@Query() dto: ItemSearchDto) { return dto; }
  @Put()
  control(@Body() dto: ItemClassDto) { return dto; }
  @Post('published')
  publish(@Body() dto: PublishedDto) { return dto; }
  @Get('filtered')
  filter(@Query() dto: FilterDto, @Query() extra: ExtraDto) { return { dto, extra }; }
  @Put('dynamic')
  dynamic(@Body() dto: DynamicDto) { return dto; }
}
