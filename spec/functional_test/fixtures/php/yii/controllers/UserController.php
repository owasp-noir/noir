<?php

namespace app\controllers;

use Yii;
use yii\rest\ActiveController;

class UserController extends ActiveController
{
    public $modelClass = 'app\models\User';

    public function actionProfile($id)
    {
        $sessionId = Yii::$app->request->cookies->get('session_id');
        $token = Yii::$app->request->headers->get('Authorization');
        return ['id' => $id, 'session' => $sessionId, 'token' => $token];
    }

    public function actionSearch()
    {
        $request = Yii::$app->request;
        $query = $request->get('q');
        $tag = $request->get('tag');
        return ['query' => $query, 'tag' => $tag];
    }
}
