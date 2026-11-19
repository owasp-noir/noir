<?php
declare(strict_types=1);
namespace App\Controller;

class ArticlesController extends AppController
{
    public function initialize(): void
    {
        parent::initialize();
    }

    public function index()
    {
        $articles = $this->paginate($this->Articles);
    }

    public function view($id = null) {}

    public function viewAll() {}

    protected function helper() {}

    private function secret() {}

    public function _internal() {}
}
