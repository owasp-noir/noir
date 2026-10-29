import express from 'express';
import { expressjwt as jwt } from 'express-jwt';
import auth from './auth';

const app = express();
const requireJwt = jwt({ secret: 's', algorithms: ['HS256'] });
const optionalJwt = jwt({ secret: 's', credentialsRequired: false, algorithms: ['HS256'] });

app.get('/feed', auth.required, (req, res) => { res.json([]) });
app.get('/alias', requireJwt, (req, res) => { res.json([]) });
app.get('/optional', auth.optional, (req, res) => { res.json([]) });
app.get('/optional-alias', optionalJwt, (req, res) => { res.json([]) });
app.get('/open', (req, res) => { res.json([]) });
