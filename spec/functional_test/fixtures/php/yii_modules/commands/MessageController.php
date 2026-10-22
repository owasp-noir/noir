<?php

namespace app\commands;

// A subclass of a built-in console command (`yii message/extract-module`):
// CLI only, never an HTTP route.
class MessageController extends \yii\console\controllers\MessageController
{
    public function actionExtractModule($moduleId)
    {
        return 0;
    }
}
