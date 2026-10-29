import { Controller, Post } from '@nestjs/common';

@Controller('logs')
export class LogsController {
  @Post()
  create() { return {}; }
}
