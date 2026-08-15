import { Controller, Get, Post, Put, Delete, Param, Query, Body, Headers, QueryMethod } from '@nestjs/common';

@Controller('users')
export class UserController {
  @Get()
  findAll() {
    return [];
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return {};
  }

  @Post()
  create(@Body() createUserDto: any) {
    return {};
  }

  @Put(':id')
  update(@Param('id') id: string, @Body() updateUserDto: any) {
    return {};
  }

  @Delete(':id')
  remove(@Param('id') id: string) {
    return {};
  }

  @Get('search')
  search(@Query('name') name: string, @Query('email') email: string) {
    return [];
  }
}

@Controller('search')
export class SearchController {
  @QueryMethod()
  find(@Body() filters: any) {
    return [];
  }

  @QueryMethod('advanced')
  advanced(@Body() dto: any) {
    return [];
  }
}

@Controller('protected')
export class ProtectedController {
  @Get()
  getProtected(@Headers('authorization') auth: string) {
    return {};
  }
}

