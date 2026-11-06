import { Module } from '@nestjs/common';
import { RouterModule, Routes } from '@nestjs/core';
import { PrivateModule } from './private/private.module';
import { PublicModule } from './public/public.module';
import { InnerModule } from './inner/inner.module';
import { OtherModule } from './other/other.module';
import { PUBLIC_PREFIX } from './prefix';

const routes: Routes = [
  { path: PUBLIC_PREFIX, module: PublicModule },
  {
    path: 'api/private',
    module: PrivateModule,
    children: [{ path: 'inner', module: InnerModule }],
  },
  // { path: 'ghost', module: OtherModule },
];

@Module({
  imports: [RouterModule.register(routes), OtherModule],
})
export class AppModule {}
