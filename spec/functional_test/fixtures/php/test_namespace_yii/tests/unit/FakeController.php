<?php

namespace tests\unit;

use yii\web\Controller;

class FakeController extends Controller
{
    public function actionDouble()
    {
        return Yii::$app->request->get('double');
    }
}
