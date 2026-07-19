component {

	// No allowedMethods map: a bare route() stays GET.
	function index( event, rc, prc ){}

	// Per-function attribute form.
	function legacy( event, rc, prc ) allowedMethods="GET,POST"{}

}
