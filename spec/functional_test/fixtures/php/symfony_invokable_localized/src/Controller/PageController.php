<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

// A class route is only a prefix once a method carries a route of its own,
// invokable or not.
#[Route('/site')]
class PageController extends AbstractController
{
    #[Route(
        path: [
            'en' => '/about-us',
            'nl' => '/over-ons',
        ],
        name: 'about',
    )]
    public function about(): Response
    {
        return new Response('about');
    }

    #[Route(['en' => '/contact', 'nl' => '/kontakt'], methods: ['GET', 'POST'])]
    public function contact(): Response
    {
        return new Response('contact');
    }

    #[Route('/page/{page<\d+>}', name: 'page')]
    public function page(int $page): Response
    {
        return new Response((string) $page);
    }

    public function __invoke(): Response
    {
        return new Response('unrouted');
    }
}

// No route on a method and nothing to invoke: the attribute routes nothing.
#[Route('/internal')]
class PrefixOnlyController
{
    public function helper(): Response
    {
        return new Response('x');
    }
}
