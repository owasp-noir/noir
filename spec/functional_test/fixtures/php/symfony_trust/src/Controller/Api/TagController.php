<?php

namespace App\Controller\Api;

use App\Form\CommentType;
use App\Form\SearchType;
use App\Form\Api\TagApiType;
use FOS\RestBundle\Controller\Annotations as Rest;
use FOS\RestBundle\Request\ParamFetcherInterface;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Annotation\Route;

#[Route('/public/tags')]
class TagController extends BaseController
{
    #[Route(methods: ['POST'], name: 'post_tag')]
    public function post(Request $request)
    {
        $form = $this->createForm(TagApiType::class);
        $form->submit($request->request->all());

        return $this->json([]);
    }

    #[Route(path: '/recent', methods: ['GET'])]
    #[Rest\QueryParam(name: 'size', requirements: '\d+', nullable: true)]
    #[Rest\QueryParam(name: 'since', key: 'from')]
    public function recent(ParamFetcherInterface $paramFetcher)
    {
        return $this->json([$paramFetcher->get('size')]);
    }

    #[Route(path: '/{id}/meta', methods: ['PATCH'])]
    #[Rest\RequestParam(name: 'value', strict: true)]
    public function meta(ParamFetcherInterface $paramFetcher, $id)
    {
        return $this->json([$paramFetcher->get('value')]);
    }

    #[Route(path: '/{id}/comment', methods: ['POST'])]
    public function comment(Request $request, $id)
    {
        $form = $this->commentForm();
        $form->handleRequest($request);

        return $this->json([]);
    }

    #[Route(path: '/search', methods: ['GET'])]
    public function search(Request $request)
    {
        $form = $this->createGetForm(SearchType::class);
        $form->submit($request->query->all(), false);

        return $this->json([]);
    }

    private function commentForm()
    {
        return $this->createForm(CommentType::class);
    }
}
