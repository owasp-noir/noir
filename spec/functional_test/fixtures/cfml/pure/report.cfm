<cfparam name="url.range" default="7">

<script>
	// Client-side JS: `form` here is a DOM node, not the CFML form scope,
	// so `action`/`submit` must NOT surface as params and must not make
	// this page POST.
	var form = document.forms[0];
	form.action = "/save";
	form.submit();

	// Server-side interpolation inside JS is still a real request read.
	var range = #url.days#;
</script>
