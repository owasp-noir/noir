<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

// Multi-line `#[Route(...)]` attributes whose `path:` sits after a
// newline+indent (and a nested multi-line `defaults: [...]`), with HTTP verbs
// given as `Request::METHOD_*` constants instead of string literals — the
// shape Shopware's storefront uses for hundreds of routes.
class StorefrontController extends AbstractController
{
    #[Route(
        path: '/account/login',
        name: 'frontend.account.login.page',
        defaults: [
            'XmlHttpRequest' => true,
        ],
        methods: [Request::METHOD_GET]
    )]
    public function loginPage(Request $request): Response
    {
        return new Response();
    }

    #[Route(
        path: '/account/login',
        name: 'frontend.account.login',
        methods: [Request::METHOD_POST]
    )]
    public function login(Request $request): Response
    {
        return new Response();
    }

    #[Route(
        path: '/account/order/{id}',
        methods: [Request::METHOD_GET, Request::METHOD_POST]
    )]
    public function order(string $id): Response
    {
        return new Response();
    }
}
