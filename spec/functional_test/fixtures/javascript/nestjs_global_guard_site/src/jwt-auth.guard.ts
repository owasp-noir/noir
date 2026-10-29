import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';

// The guard every route runs through.
@Injectable()
export class JwtAuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest();
    if (!req.headers.authorization) throw new UnauthorizedException();
    return true;
  }
}
