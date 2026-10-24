<?php

namespace App\Controller;

use App\Entity\User;
use App\Form\EditType;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Annotation\Route;
use Symfony\Component\Security\Http\Attribute\IsGranted;

class EntryController extends AbstractController
{
    #[Route(path: '/feed/{token}', methods: ['GET'])]
    #[IsGranted('PUBLIC_ACCESS')]
    #[ParamConverter('user', class: User::class)]
    public function feed(User $user)
    {
        return $this->render('feed.xml.twig');
    }

    #[Route(path: '/share/{uid}', methods: ['GET'])]
    #[IsGranted('PUBLIC_ACCESS')]
    public function share($uid)
    {
        return $this->render('share.html.twig');
    }

    #[Route(path: '/list/{page}', methods: ['GET'])]
    #[IsGranted('LIST')]
    public function list(Request $request, $page)
    {
        return $this->show($request, $page);
    }

    #[Route(path: '/edit/{id}', methods: ['POST'])]
    public function edit(Request $request, $id)
    {
        $form = $this->createForm(EditType::class);
        $form->handleRequest($request);

        return $this->render('edit.html.twig');
    }

    private function show(Request $request, $page)
    {
        $sort = $request->query->get('sort');
        $filter = $request->query->all('filter');

        return $this->render('list.html.twig');
    }
}
