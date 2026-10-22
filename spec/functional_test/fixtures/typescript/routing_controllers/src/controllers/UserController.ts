import {
  Authorized,
  Body,
  CookieParam,
  Delete,
  Get,
  HeaderParam,
  JsonController,
  Param,
  Post,
  QueryParam,
} from 'routing-controllers';

@JsonController('/users')
export class UserController {
  @Get('/')
  getAll(@QueryParam('limit') limit: number) {
    return [];
  }

  @Get('/:id')
  getOne(@Param('id') id: number) {
    return { id };
  }

  @Authorized()
  @Post('/')
  create(@Body() user: any, @HeaderParam('authorization') token: string) {
    return user;
  }

  @Delete('/:id')
  remove(@Param('id') id: number, @CookieParam('session') session: string) {
    return {};
  }
}
