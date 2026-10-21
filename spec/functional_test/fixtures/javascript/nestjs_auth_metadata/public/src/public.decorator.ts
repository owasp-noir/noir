import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
// Same metadata under a name no list of "public" decorators would know.
export const OpenToGuests = () => SetMetadata(IS_PUBLIC_KEY, true);
