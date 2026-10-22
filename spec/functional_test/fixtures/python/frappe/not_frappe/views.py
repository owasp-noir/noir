from registry import Registry

frappe = Registry()


@frappe.whitelist()
def not_an_endpoint(x):
    return x
