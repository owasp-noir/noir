import { CanActivate, ExecutionContext, Injectable, SetMetadata, applyDecorators } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ApiBearerAuth } from '@nestjs/swagger';
import { AuthService } from './auth.service';

export const AUTH_ROUTE = 'auth_route';

export type RouteOptions = { public?: boolean; sharedLink?: boolean; admin?: boolean; permission?: string | false };

const getRouteOptions = (reflector: Reflector, target: Function) => {
  return reflector.getAllAndOverride<RouteOptions | undefined>(AUTH_ROUTE, [target]);
};

export const Authenticated = (options: RouteOptions = {}): MethodDecorator => {
  const decorators: MethodDecorator[] = [SetMetadata(AUTH_ROUTE, options)];
  if (!options.public) {
    decorators.push(ApiBearerAuth());
  }
  return applyDecorators(...decorators);
};

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private reflector: Reflector,
    private authService: AuthService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const options = getRouteOptions(this.reflector, context.getHandler());
    if (!options) {
      throw new Error('Route does not declare @Authenticated()');
    }

    if (options.public) {
      return true;
    }

    const request = context.switchToHttp().getRequest();
    request.user = await this.authService.authenticate(request, options);
    return true;
  }
}
