<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\Routing\Attribute\Route;

class PageController extends AbstractController
{
    #[Route(path: '/a1/x', name: 'a1')]
    public function a1()
    {
        return $this->json([]);
    }

    #[Route(path: '/other/x', name: 'other')]
    public function other()
    {
        return $this->json([]);
    }

    #[Route(path: '/host/x', name: 'host')]
    public function host()
    {
        return $this->json([]);
    }

    #[Route(path: '/m/x', name: 'm')]
    public function m()
    {
        return $this->json([]);
    }

    #[Route(path: '/api/x', name: 'api')]
    public function api()
    {
        return $this->json([]);
    }

    #[Route(path: '/page/{slug}', name: 'page')]
    public function page()
    {
        return $this->json([]);
    }
}
