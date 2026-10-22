<?php

namespace app\modules\api\v1\controllers;

use yii\web\Controller;

// `controllers/` is not directly under `modules/<id>/`: the module id is
// unknown, so the route keeps the controller-only form.
class ItemController extends Controller
{
    public function actionList()
    {
        return [];
    }
}
