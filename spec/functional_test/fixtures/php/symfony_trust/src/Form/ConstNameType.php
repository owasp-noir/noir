<?php

namespace App\Form;

use Symfony\Component\Form\AbstractType;
use Symfony\Component\Form\FormBuilderInterface;

class ConstNameType extends AbstractType
{
    public const NAME = 'cn';

    public function buildForm(FormBuilderInterface $builder, array $options): void
    {
        $builder->add('title');
    }

    public function getBlockPrefix(): string
    {
        return self::NAME;
    }
}
