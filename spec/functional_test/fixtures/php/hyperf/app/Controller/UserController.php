<?php

declare(strict_types=1);

namespace App\Controller;

use Hyperf\HttpServer\Annotation\Controller;
use Hyperf\HttpServer\Annotation\GetMapping;
use Hyperf\HttpServer\Annotation\PostMapping;
use Hyperf\HttpServer\Annotation\RequestMapping;
use Hyperf\HttpServer\Contract\RequestInterface;

#[Controller(prefix: "/users")]
class UserController
{
    #[GetMapping(path: "/")]
    public function index(RequestInterface $request)
    {
        $page = $request->query('page');
        return [];
    }

    #[PostMapping(path: "/")]
    public function store(RequestInterface $request)
    {
        $name = $request->input('name');
        return [];
    }

    #[RequestMapping(path: "/{id}", methods: "GET,DELETE")]
    public function show(int $id, RequestInterface $request)
    {
        $token = $request->header('X-Auth-Token');
        return [];
    }
}
