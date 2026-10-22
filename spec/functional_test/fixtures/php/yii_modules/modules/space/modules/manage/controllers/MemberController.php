<?php

namespace app\modules\space\modules\manage\controllers;

use yii\web\Controller;

// A nested module chains both ids: `space/manage/member/index`.
class MemberController extends Controller
{
    public function actionIndex()
    {
        return $this->render('index');
    }
}
