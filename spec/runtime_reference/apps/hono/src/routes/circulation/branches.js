import { Hono } from 'hono';
import { createDesk } from './desk.js';

export const branches = new Hono();
branches.route('/central', createDesk('Central library'));
branches.route(process.env.MOBILE_MOUNT || '/mobile', createDesk('Mobile library'));
