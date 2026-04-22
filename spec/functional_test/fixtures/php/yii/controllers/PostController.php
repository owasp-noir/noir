<?php

namespace app\controllers;

use Yii;
use yii\web\Controller;
use yii\web\NotFoundHttpException;

class PostController extends Controller
{
    public function actionIndex()
    {
        $page = Yii::$app->request->get('page');
        $limit = Yii::$app->request->get('limit');
        return $this->render('index', ['page' => $page, 'limit' => $limit]);
    }

    public function actionView($id)
    {
        return $this->render('view', ['id' => $id]);
    }

    public function actionCreate()
    {
        $title = Yii::$app->request->post('title');
        $body = Yii::$app->request->post('body');
        $csrf = Yii::$app->request->headers->get('X-CSRF-Token');
        return $this->render('create', ['title' => $title, 'body' => $body]);
    }
}
