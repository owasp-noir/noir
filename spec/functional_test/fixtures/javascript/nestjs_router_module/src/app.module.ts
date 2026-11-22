import { Controller, Get, Module } from '@nestjs/common';
import { RouterModule, Routes } from '@nestjs/core';
import { PrivateModule } from './private/private.module';
import { PublicModule } from './public/public.module';
import { InnerModule } from './inner/inner.module';
import { OtherModule } from './other/other.module';
import { PUBLIC_PREFIX } from './prefix';

const projected = 'branch' + process.env.BRANCH;

@Controller('optional')
class OptionalController {
  @Get()
  root() { return 'optional'; }
}

@Module({ controllers: [OptionalController] })
class OptionalModule {}

@Controller(['quoted${literal}', `template${process.env.NAME}`, projected])
class PatternController {
  @Get()
  root() { return 'pattern'; }
}

const routes: Routes = [
  { path: PUBLIC_PREFIX, module: PublicModule },
  {
    path: 'api/private',
    module: PrivateModule,
    children: [{ path: 'inner', module: InnerModule }],
  },
  { path: process.env.OTHER_PREFIX, module: OptionalModule },
  // { path: 'ghost', module: OtherModule },
];

@Module({
  controllers: [PatternController],
  imports: [RouterModule.register(routes), OtherModule],
})
export class AppModule {}
