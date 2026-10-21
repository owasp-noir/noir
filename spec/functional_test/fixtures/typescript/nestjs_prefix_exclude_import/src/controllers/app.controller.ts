import { Controller, Get, Post } from '@nestjs/common';

@Controller()
export class AppController {
  @Get('.well-known/app')
  getWellKnown() {
    return {};
  }

  @Get('custom.css')
  getCustomCss() {
    return '';
  }

  // The `custom.css` exclude names GET only.
  @Post('custom.css')
  setCustomCss() {
    return '';
  }

  @Get('version')
  getVersion() {
    return '1';
  }
}
