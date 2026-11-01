<?php
namespace App\Controller {
    use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
    use Symfony\Component\Routing\Attribute\Route;
    use Symfony\Component\Security\Http\Attribute\IsGranted;

    #[Route('/ns')]
    #[IsGranted('ROLE_ADMIN')]
    class NsController extends AbstractController
    {
        #[Route('/x', methods: ['GET'])]
        public function x(): void {}
    }
}
