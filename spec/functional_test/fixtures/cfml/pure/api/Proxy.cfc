component extends="framework.Proxy" {

	// script syntax, `remote` as a leading modifier
	remote string function echo( required string text ) {
		return arguments.text;
	}

	// script syntax, `access` as a trailing attribute
	string function ping() access="remote" {
		return "pong";
	}

	remote any function search( term, numeric page = 1 ) returnFormat='plain' {
		return arrayNew(1);
	}

	private function helper( hidden ) {
		return hidden;
	}
}
