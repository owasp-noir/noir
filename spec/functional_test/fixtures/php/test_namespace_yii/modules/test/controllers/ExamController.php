<?php

namespace app\modules\test\controllers;

use yii\web\Controller;

// Routed as `test/exam/run`: `test` is the module id of the exam feature,
// not a test directory.
class ExamController extends Controller
{
    public function actionRun()
    {
        return Yii::$app->request->get('level');
    }
}
