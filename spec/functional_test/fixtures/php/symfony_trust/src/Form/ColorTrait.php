<?php

namespace App\Form;

use Symfony\Component\Form\FormBuilderInterface;

trait ColorTrait
{
    protected function addColor(FormBuilderInterface $builder): void
    {
        $builder->add('color', ColorType::class);
    }
}
