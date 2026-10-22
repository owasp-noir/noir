<?php
use Phalcon\Mvc\Controller;

/**
 * @RoutePrefix('/api/products')
 */
class ProductsController extends Controller
{
    /**
     * @Get('/search')
     */
    public function searchAction()
    {
        $q = $this->request->getQuery('q');
    }

    /**
     * @Route('/save', methods={'POST', 'PUT'})
     */
    public function saveAction()
    {
        $name = $this->request->getPost('name');
    }
}
