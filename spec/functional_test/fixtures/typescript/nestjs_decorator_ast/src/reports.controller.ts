import { Body, Controller, Get, Param, ParseFilePipe, ParseIntPipe, Post, Query, UploadedFile, Version } from '@nestjs/common';
import { ApiOperation } from '@nestjs/swagger';
import { CreateReportDto } from './create-report.dto';

// @Controller('ghost') above the real one is a comment, not a controller.
@Controller({ path: 'reports', version: '1' })
export class ReportsController {
  // Route-looking text inside a string is not a route.
  @ApiOperation({ summary: 'List (all) reports', description: 'v0: @Get("legacy") legacy() {}' })
  @Get()
  list(@Query('sort') sort: string) {
    return [];
  }

  @Get(
    ':id',
  )
  @Version(
    '2',
  )
  find(
    @Param('id', ParseIntPipe) id: number,
    @Query('fields)') fields: string,
  ) {
    return id;
  }

  /* @Post('legacy') */
  @Post()
  create(@Body() dto: CreateReportDto) {
    return dto;
  }

  @Post('upload')
  upload(@UploadedFile(new ParseFilePipe({ validators: [] })) document: Express.Multer.File) {
    return document;
  }
}
