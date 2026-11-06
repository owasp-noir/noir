import { Module } from '@nestjs/common';
import { RouterModule } from '@nestjs/core';
import { UsersModule } from './users/users.module';

@Module({ imports: [RouterModule.register([{ path: 'a', module: UsersModule }]), UsersModule] })
export class AppModule {}
