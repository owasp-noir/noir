<?php
namespace app\controllers;

use yii\web\Controller;
use yii\web\Response;

class ShopController extends Controller
{
    public function actionIndex(): string
    {
        return $this->render('index');
    }

    public function actionView(int $id): string|Response
    {
        return $this->render('view', ['id' => $id]);
    }

    public function actionCart(): ?array
    {
        return [];
    }

    protected function actionHidden(): string
    {
        return '';
    }
}
