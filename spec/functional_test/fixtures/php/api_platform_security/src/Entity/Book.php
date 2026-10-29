<?php

namespace App\Entity;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Delete;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\Metadata\Post;
use ApiPlatform\Metadata\QueryParameter;
use Symfony\Component\Serializer\Attribute\Groups;

#[ApiResource(
    uriTemplate: '/admin/books{._format}',
    operations: [
        new GetCollection(),
        new Post(),
    ],
    denormalizationContext: ['groups' => ['Book:write']],
    security: 'is_granted("ROLE_ADMIN")',
)]
#[ApiResource(
    operations: [
        new GetCollection(),
        new Delete(security: 'object.owner === user'),
    ],
)]
class Book
{
    #[Groups(['Book:write'])]
    #[QueryParameter(filter: new PartialSearchFilter())]
    public string $title;

    #[Groups(['Book:read'])]
    public string $isbn;
}
