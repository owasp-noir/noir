<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\Routing\Annotation\Route;
use Symfony\Component\Security\Http\Attribute\IsGranted;

#[IsGranted('ROLE_ADMIN')]
class StatsController extends AbstractController
{
    #[Route(path: '/public/stats', methods: ['GET'])]
    public function stats()
    {
        return $this->json([]);
    }
}
