const Router = require('restify-router').Router;
const adminRouter = new Router();
adminRouter.get('/stats', (req, res, next) => { res.send('ok'); next(); });
module.exports = { adminRouter };
