import { os } from '@orpc/server';

export const pub = os.$context<{ cache: Map<string, Array<number>> }>();
