import { Controller, Sse, UploadedFile, UploadedFiles, Post, HostParam, Get, Headers, Query } from '@nestjs/common';

// Versioned controller with a multi-version array — Nest expands this
// into one route per version.
@Controller({ path: 'events', version: ['1', '2'] })
export class EventsController {
  // Server-sent events: `@Sse` is GET under the hood.
  @Sse('stream')
  stream() {
    return null;
  }

  // Bare @Sse() — no path segment.
  @Sse()
  liveAll() {
    return null;
  }
}

// Subdomain routing surfaces a @HostParam path-like parameter.
@Controller({ host: ':account.example.com', path: 'tenant' })
export class TenantController {
  @Get(':slug')
  describe(@HostParam('account') account: string) {
    return { account };
  }

  @Get('lookup')
  lookup(@Query() query: Record<string, string>, @Headers() headers: Record<string, string>) {
    return { query, headers };
  }
}

// Multipart upload with explicit and implicit decorators. Multer
// integration is the dominant way Nest apps accept files.
@Controller('uploads')
export class UploadsController {
  @Post('avatar')
  uploadAvatar(@UploadedFile('avatar') file: any) {
    return file;
  }

  @Post('attachments')
  uploadAttachments(@UploadedFiles('files') files: any[]) {
    return files;
  }

  @Post('blob')
  uploadBlob(@UploadedFile() file: any) {
    return file;
  }

  @Post('bulk')
  uploadBulk(@UploadedFiles() files: any[]) {
    return files;
  }

  @Post('public')
  uploadPublic(@UploadedFile() file: any) {
    return file;
  }

  // Commented-out decorator must NOT be reported as a real route.
  // @Get('/legacy/path')
  // legacy() { return null; }
}

@Controller('health')
export class HealthController {
  @Get()
  check() {
    return { ok: true };
  }
}
