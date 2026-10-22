import { CanActivate, ExecutionContext, Injectable, SetMetadata } from '@nestjs/common';
import { Reflector } from '@nestjs/core';

export const SECURED = 'secured';
export const Secured = (options = {}) => SetMetadata(SECURED, options);

// Opt-in: only routes carrying the metadata are authenticated.
@Injectable()
export class SessionAuthGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const options = this.reflector.get(SECURED, context.getHandler());
    if (!options) return true;
    return Boolean(context.switchToHttp().getRequest().session?.user);
  }
}
