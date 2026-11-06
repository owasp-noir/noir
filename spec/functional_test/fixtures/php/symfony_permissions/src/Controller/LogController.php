<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\Security\Http\Attribute\IsGranted;

class LogController extends AbstractController
{
    #[Route(path: '/logs', name: 'logs')]
    public function show()
    {
        $this->denyAccessUnlessGranted('@system.show_logs');

        return $this->json([]);
    }

    #[Route(path: '/api/info', name: 'info')]
    public function info()
    {
        return $this->json([]);
    }

    #[Route(path: '/maybe/info', name: 'maybe')]
    public function maybe()
    {
        return $this->json([]);
    }

    #[Route(path: '/open/info', name: 'open')]
    public function open()
    {
        return $this->json([]);
    }

    #[Route(path: '/cmp/x', name: 'cmp')]
    public function cmp()
    {
        return $this->json([]);
    }

    #[Route(path: '/str/x', name: 'str')]
    public function str()
    {
        return $this->json([]);
    }

    #[Route(path: '/role/x', name: 'role')]
    public function role()
    {
        return $this->json([]);
    }

    #[Route(path: '/dyn', name: 'dyn')]
    public function dyn($attr)
    {
        $this->denyAccessUnlessGranted("{$attr}");

        return $this->json([]);
    }

    #[Route(path: '/rolecheck', name: 'rolecheck')]
    public function rolecheck()
    {
        $this->denyAccessUnlessGranted('ROLE_ADMIN');

        return $this->json([]);
    }

    #[Route(path: '/voted', name: 'voted')]
    #[IsGranted('@parts.read')]
    public function voted()
    {
        return $this->json([]);
    }

    #[Route(path: '/dyncheck', name: 'dyncheck')]
    public function dyncheck($attr)
    {
        if (!$this->isGranted("perm.{$attr}")) {
            throw $this->createAccessDeniedException();
        }

        return $this->json([]);
    }

    #[Route(path: '/perm/x', name: 'perm')]
    public function perm()
    {
        return $this->json([]);
    }

    #[Route(path: '/plain/x', name: 'plain')]
    public function plain()
    {
        return $this->json([]);
    }

    #[Route(path: '/mixed/x', name: 'mixed')]
    public function mixed()
    {
        return $this->json([]);
    }

    #[Route(path: '/full/x', name: 'full')]
    public function full()
    {
        return $this->json([]);
    }
}
