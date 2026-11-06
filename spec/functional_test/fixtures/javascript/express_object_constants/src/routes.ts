import express from 'express';
import { accountApiPrefix, experienceRoutes } from './const';

const router = express.Router();

router.post(`${experienceRoutes.verification}/password`, (req, res) => res.json({}));
router.post(`${experienceRoutes.mfa}`, (req, res) => res.json({}));

const pathname = `${accountApiPrefix}/tokens`;
router.get(pathname, (req, res) => res.json([]));
router.delete(`${pathname}/:id`, (req, res) => res.json({}));

// Not a constant this file can read: kept as a template, as before.
router.get(`${settings.base}/status`, (req, res) => res.json({}));

export default router;
