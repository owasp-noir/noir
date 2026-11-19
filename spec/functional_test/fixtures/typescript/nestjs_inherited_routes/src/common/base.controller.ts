import { Body, Delete, Get, Param, Post, Query } from '@nestjs/common';

export abstract class BaseController<T> {
  @Get()
  findAll(@Query('page') page: number) { return []; }

  @Get(':id')
  findOne(@Param('id') id: string) { return {}; }

  @Post()
  create(@Body() dto: T) { return dto; }

  @Delete(':id')
  remove(@Param('id') id: string) { return {}; }
}
