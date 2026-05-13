<?php

namespace App\Controller;

class ArticlesController extends AppController
{
    public function view($id)
    {
        $article = ArticleService::find($id);
        return $this->jsonArticle($article);
    }

    public function add()
    {
        $payload = ArticlePayload::fromRequest($this->request);
        return ArticleService::create($payload);
    }
}
