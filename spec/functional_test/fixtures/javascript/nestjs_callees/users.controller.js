import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common'

@Controller('users')
export class UsersController {
  @Post()
  create(@Body() body) {
    const actor = this.authService.actor()
    const user = this.usersService.create(body, actor)
    AuditLog.write('nestjs:create')

    return this.presenter.user(user)
  }

  @Get(':id')
  findOne(@Param('id') id, @Query('include') include) {
    const user = this.usersService.findOne(id)

    return buildProfile(user, include)
  }
}
