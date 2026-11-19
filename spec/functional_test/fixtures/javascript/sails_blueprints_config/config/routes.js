module.exports.routes = {
  'GET /':                   { action: 'view-homepage-or-redirect' },
  'PUT /api/v1/entrance/login': { action: 'entrance/login' },
  'POST /api/v1/account/update-password': { action: 'account/update-password' },
};
