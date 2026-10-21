import { CanActivate, ExecutionContext, Injectable, SetMetadata, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';

export const RequireRoles = (...roles: string[]) => SetMetadata('roles', roles);

@Injectable()
export class TokenAuthGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const user = context.switchToHttp().getRequest().user;
    if (!user) throw new UnauthorizedException();
    // Reached only by callers who logged in.
    const roles = this.reflector.get<string[]>('roles', context.getHandler());
    if (!roles) return true;
    return roles.includes(user.role);
  }
}
