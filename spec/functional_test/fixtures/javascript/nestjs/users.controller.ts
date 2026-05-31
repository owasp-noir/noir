import { Controller, Get, Post, Put, Delete, Param, Query, Body, Headers, Req, UploadedFile, UseGuards, UseInterceptors, Version } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';

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

@Controller('protected')
export class ProtectedController {
  @Get()
  getProtected(@Headers('authorization') auth: string) {
    return {};
  }
}

@Controller('admin')
export class AdminController {
  @Get('reports/:id')
  @UseGuards(AuthGuard)
  report(@Param('id') id: string, @Req() req: any) {
    const include = req.query.include;
    const token = req.headers['x-token'];
    return { id, include, token };
  }

  @Post('upload')
  @UseInterceptors(FileInterceptor('avatar'))
  upload(@UploadedFile() file: any) {
    return { file };
  }

  @Version('2')
  @Get('versioned')
  versioned() {
    return {};
  }
}
