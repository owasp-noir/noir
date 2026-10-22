import { Controller, Get, Post } from '@nestjs/common';

@Controller('users')
export class UserController {
  @Get()
  findAll() {
    return [];
  }

  // The regex body holds an unpaired quote. Without a regex state the
  // comment stripper flipped into (and out of) string state for the rest of
  // the file, which both un-blanked the commented-out decorator below and
  // let the '/*' in a plain string open a block comment.
  escape(str: string) { return str.replace(/'/g, '&#39;'); }

  private readonly blockOpen = '/*';

  // @Get('legacy-removed')
  @Post('create')
  create() { return {}; }
}
