import frappe
from frappe.model.document import Document


class Book(Document):
    @frappe.whitelist()
    def mark_lost(self, reason):
        self.status = "Lost"
        self.save()


@frappe.whitelist()
def get_availability(book):
    return frappe.db.get_value("Book", book, "status")
