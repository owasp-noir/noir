import { Controller, Get, Post, Query, Body } from '@nestjs/common';
import { UsersService } from './users.service';
import { Runner } from './runner';

@Controller('users')
export class UsersController {
  constructor(
    private readonly usersService: UsersService,
    private readonly runner: Runner,
  ) {}

  @Post('export')
  exportReport(@Body('target') target: string) {
    return this.usersService.exportReport(target);
  }

  @Get('search')
  search(@Query('name') name: string) {
    return this.usersService.search(name);
  }

  @Get('ambiguous')
  ambiguous(@Query('q') q: string) {
    return this.runner.run(q);
  }

  @Get('cycle')
  cycle() {
    return this.usersService.pingA(3);
  }

  @Get('count')
  count() {
    return this.usersService.count();
  }
}
