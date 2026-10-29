import { Injectable, NestMiddleware, HttpException, HttpStatus } from '@nestjs/common';

@Injectable()
export class AuthMiddleware implements NestMiddleware {
  use(req: any, res: any, next: () => void) {
    if (!req.headers.authorization) {
      throw new HttpException('Not authorized.', HttpStatus.UNAUTHORIZED);
    }
    next();
  }
}

@Injectable()
export class LogMiddleware implements NestMiddleware {
  use(req: any, res: any, next: () => void) {
    next();
  }
}
