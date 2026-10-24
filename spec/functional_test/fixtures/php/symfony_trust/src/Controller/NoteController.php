<?php

namespace App\Controller;

use App\Form\NoteType;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\Form\FormFactoryInterface;
use Symfony\Component\HttpFoundation\Request;

class NoteController extends AbstractController
{
    public function __construct(private readonly FormFactoryInterface $formFactory)
    {
    }

    public function save(Request $request)
    {
        $data = json_decode($request->getContent(), true);
        $form = $this->formFactory->createNamed('', NoteType::class);
        $form->submit($data);

        return $this->json([]);
    }
}
