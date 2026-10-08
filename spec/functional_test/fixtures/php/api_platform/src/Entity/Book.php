<?php

namespace App\Entity;

use ApiPlatform\Metadata\ApiResource;
use Doctrine\ORM\Mapping as ORM;

/**
 * Default operations: #[ApiResource(uriTemplate: '/not-a-route')] in a comment.
 */
#[ApiResource]
#[ORM\Entity(repositoryClass: BookRepository::class)]
class Book
{
    #[ORM\Id]
    public ?int $id = null;
}
