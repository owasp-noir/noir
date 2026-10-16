<?php

namespace app\modules\admin\controllers;

use yii\web\Controller;

// Routed as `admin/setting/basic`: a module controller is reachable only
// through its module id.
class SettingController extends Controller
{
    public function actionBasic()
    {
        return Yii::$app->request->get('tab');
    }
}
