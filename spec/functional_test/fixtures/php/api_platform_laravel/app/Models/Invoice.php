<?php

namespace App\Models;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Post;
use Illuminate\Database\Eloquent\Model;

// Laravel's route_prefix is only the default: routePrefix replaces it.
#[ApiResource(routePrefix: 'billing', operations: [new Post(uriTemplate: 'calculate')])]
class Invoice extends Model
{
}
