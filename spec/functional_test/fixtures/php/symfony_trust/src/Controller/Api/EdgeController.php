<?php

namespace App\Controller\Api;

use App\Entity\User;
use App\Form\CommentType;
use App\Form\ConstNameType;
use App\Form\SearchType;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Annotation\Route;
use Symfony\Component\Security\Http\Attribute\IsGranted;

#[Route('/public/edge')]
class EdgeController extends BaseController
{
    public const LIST = '/list';

    // A path given by a constant is unknown: no route, not the class prefix.
    #[Route(self::LIST, methods: ['GET'])]
    public function list()
    {
        return $this->json([]);
    }

    /**
     * @Route(name="edge_ajax", condition="request.isXmlHttpRequest()", path="/ajax")
     */
    public function ajax()
    {
        return $this->json([]);
    }

    #[Route('/named', methods: ['POST'])]
    #[IsGranted('ROLE_ADMIN')]
    public function named(Request $request)
    {
        $name = $this->formName;
        $form = $this->container->get('form.factory')->createNamed($name, CommentType::class);
        $form->handleRequest($request);
        return $this->json([]);
    }
    #[Route('/const-form', methods: ['POST'])]
    public function constForm(Request $request)
    {
        $form = $this->createForm(ConstNameType::class);
        $form->handleRequest($request);
        return $this->json([]);
    }

    #[Route('/entity-first', methods: ['POST'])]
    public function entityFirst(Request $request)
    {
        $form = $this->make(User::class, SearchType::class);
        $form->handleRequest($request);
        return $this->json([]);
    }

    private function make(string $entity, string $type)
    {
        return $this->createForm($type, new $entity());
    }
}
