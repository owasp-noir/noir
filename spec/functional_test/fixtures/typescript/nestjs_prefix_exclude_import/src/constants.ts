import { RequestMethod } from '@nestjs/common';

export const excludePaths = [
  '/.well-known/app',
  // '/version',
  { path: 'custom.css', method: RequestMethod.GET },
];
