const Router = require('restify-router').Router;
const router = new Router();
router.add('/v1', require('./v1'));
router.get('/status', (req, res, next) => { res.send('ok'); next(); });
module.exports = router;
