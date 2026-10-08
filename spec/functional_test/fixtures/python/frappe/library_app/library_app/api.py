import frappe


@frappe.whitelist(allow_guest=1)
def get_books(category=None, limit=20):
    return frappe.get_all("Book", filters={"category": category}, limit=limit)


@frappe.whitelist(methods=["POST"])
def issue_book(book, member, **kwargs):
    due = kwargs.get("due_date")
    frappe.get_doc({"doctype": "Book Issue", "book": book, "member": member, "due_date": due}).insert()


@frappe.whitelist(
    allow_guest=True,
    xss_safe=True,
    methods="GET",
)
def search(q):
    return frappe.db.get_list("Book", filters={"title": ["like", f"%{q}%"]})


@frappe.whitelist()
def stats():
    member = frappe.form_dict.get("member")
    status = frappe.form_dict.status
    return frappe.db.count("Book Issue", {"member": member, "status": status})


def _helper():
    return None
