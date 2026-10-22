component {

	this.allowedMethods = {
		index  : "GET",
		new    : "GET",
		create : "POST,PUT",
		show   : "GET",
		edit   : "GET",
		update : "POST,PUT,PATCH",
		delete : "DELETE"
	};

	function index( event, rc, prc ){}
	function show( event, rc, prc ){}

}
