<?php

namespace App\Entity;

use ApiPlatform\Metadata as API;

#[API\Get(uriTemplate: '/categories/{slug}')]
#[API\GetCollection]
#[API\Post('/categories/import')]
final class Category
{
    public string $slug = '';
}
