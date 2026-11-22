import type * as Models from './dtos';
import type { Update as ImportedUpdate } from './dtos';
import type { CreateItemDto as Missing } from './not-present';
import { Body, Controller, Get, Headers, Param, Patch, Post, Query } from '@nestjs/common';
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

  @Patch('edit')
  edit(@Body() dto: ImportedUpdate, @Body('context') context: string, @Headers('if-match') etag: string) {
    return { dto, context, etag };
  }

  @Get('scope/:id/*rest')
  scope(@Param() { id, rest }: Models.Scope, @Headers() headers: Models.ConditionalHeaders) {
    return { id, rest, headers };
  }

  @Post('attributes')
  attributes(@Body() attributes: Models.Attributes) { return attributes; }

  @Post('mixed')
  mixed(@Body() known: RenameItemDto, @Body() raw: Missing, @Query() unknown: Missing) {
    return { known, raw, unknown };
  }

  @Post('union')
  union(@Body() dto: Array<CreateItemDto> | Array<RenameItemDto>) { return dto; }

  @Post('raw')
  raw(@Body() body: Record<string, unknown>) {
    return body;
  }
}
