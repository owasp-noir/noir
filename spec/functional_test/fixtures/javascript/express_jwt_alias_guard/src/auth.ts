import { expressjwt as jwt } from 'express-jwt';

const auth = {
  required: jwt({ secret: 's', algorithms: ['HS256'] }),
  optional: jwt({ secret: 's', credentialsRequired: false, algorithms: ['HS256'] }),
};

export default auth;
