<?php
// Regression guard: Yii's console controllers expose CLI commands
// (`yii migrate/up`, `yii fixture/load`), not HTTP routes. None of
// the action methods below should surface as endpoints in the
// fixture's expected list.
namespace app\commands;

use yii\console\Controller;

class MigrateController extends Controller
{
    public function actionUp($limit = 0)
    {
        return 0;
    }

    public function actionDown($limit = 0)
    {
        return 0;
    }
}
