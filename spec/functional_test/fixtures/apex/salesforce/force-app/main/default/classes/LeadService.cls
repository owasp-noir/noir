global class LeadService {
    webservice static Id createLead(String lastName, String company) {
        Lead l = new Lead(LastName = lastName, Company = company);
        insert l;
        return l.Id;
    }

    webservice String note;
}
