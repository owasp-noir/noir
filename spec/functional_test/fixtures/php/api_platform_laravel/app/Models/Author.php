<?php

namespace App\Models;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Get;
use ApiPlatform\Metadata\GetCollection;
use Illuminate\Database\Eloquent\Model;

#[ApiResource(operations: [new GetCollection(), new Get()])]
class Author extends Model
{
}
