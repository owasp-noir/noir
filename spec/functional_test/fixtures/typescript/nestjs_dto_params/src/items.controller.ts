import { Body, Controller, Get, Patch, Post, Query } from '@nestjs/common';
import { CreateItemDto, ListItemsQueryDto, RenameItemDto } from './dtos';
import { SharedFilterDto } from '@acme/shared';

@Controller('items')
export class ItemsController {
  @Post()
  create(@Body() body: CreateItemDto) {
    return body;
  }

  @Get()
  list(@Query() query: ListItemsQueryDto) {
    return query;
  }

  @Patch(':id')
  rename(@Body() body: RenameItemDto) {
    return body;
  }

  @Post(':id/actions')
  act(@Body() body: { payload: Record<string, unknown>; status: string }) {
    return body;
  }

  @Get('shared')
  shared(@Query() filter: SharedFilterDto) {
    return filter;
  }

  @Post('raw')
  raw(@Body() body: Record<string, unknown>) {
    return body;
  }
}
