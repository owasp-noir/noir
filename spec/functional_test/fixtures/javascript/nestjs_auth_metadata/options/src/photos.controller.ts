import { Controller, Delete, Get, Post } from '@nestjs/common';
import { Authenticated } from './auth.guard';

@Controller('photos')
export class PhotosController {
  @Get('ping')
  @Authenticated({ public: true })
  ping() {}

  @Get(':id')
  @Authenticated({ permission: 'photo.read', sharedLink: true })
  findOne() {}

  @Post()
  @Authenticated({ permission: 'photo.create' })
  create() {}

  @Delete(':id')
  @Authenticated({ admin: true })
  remove() {}

  @Get('me')
  @Authenticated({ permission: false })
  me() {}

  @Get('legacy')
  legacy() {}
}
