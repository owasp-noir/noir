import { Module } from '@nestjs/common';
import { RouterModule } from '@nestjs/core';
import { AdminModule } from './admin/admin.module';
import { ZooModule } from './zoo/zoo.module';
import { SharedModule } from './shared/shared.module';
import { StrModule } from './str/str.module';

const doc = "RouterModule.register([{ path: 'str', module: StrModule }])";

@Module({
  imports: [
    RouterModule.register([
      { path: 'admin', module: AdminModule },
      { path: 'api/zoo', module: ZooModule },
    ]),
    AdminModule, ZooModule, SharedModule, StrModule,
  ],
})
export class AppModule {}
