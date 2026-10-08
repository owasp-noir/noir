<?php

namespace App\Entity;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Delete;
use ApiPlatform\Metadata\Get;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\Metadata\HeaderParameter;
use ApiPlatform\Metadata\HttpOperation;
use ApiPlatform\Metadata\Link;
use ApiPlatform\Metadata\NotExposed;
use ApiPlatform\Metadata\Post;
use ApiPlatform\Metadata\Put;
use ApiPlatform\Metadata\QueryParameter;

#[ApiResource(
    shortName: 'AdminReview',
    routePrefix: '/admin',
    operations: [
        new GetCollection(
            parameters: [
                'rating' => new QueryParameter(),
                'search' => new QueryParameter(key: 'q'),
                'X-Tenant' => new HeaderParameter(),
            ],
            itemUriTemplate: '/reviews/{id}'
        ),
        new Get(), // don't cache: comments must not leak into the list
        // A routeName operation reuses an existing route and gets none.
        new Get(routeName: 'admin_review_export'),
        new Put(uriTemplate: '/reviews/{id}/moderate{._format}'),
        new HttpOperation(method: HttpOperation::METHOD_OPTIONS, uriTemplate: '/reviews/cache'),
    ],
)]
#[ApiResource(
    uriTemplate: '/books/{bookId}/reviews{._format}',
    uriVariables: ['bookId' => new Link(toProperty: 'book', fromClass: Book::class)],
    operations: [
        new GetCollection(),
        new NotExposed(uriTemplate: '/books/{bookId}/reviews/{id}'),
        new Post(),
        new Delete(uriTemplate: '/books/{bookId}/reviews/{id}'),
    ],
)]
class BookReview
{
    public ?Book $book = null;
}
