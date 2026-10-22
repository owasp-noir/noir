public without sharing class CaseController {
    @AuraEnabled(cacheable=true)
    public static List<Case> getCases(String status) {
        return [SELECT Id FROM Case WHERE Status = :status];
    }

    @AuraEnabled
    public static Case updateCase(Id caseId, Map<String, Object> fields) {
        return null;
    }

    // Instance @AuraEnabled methods are not invocable actions.
    @AuraEnabled
    public String label() { return 'x'; }

    public class CaseWrapper {
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled
        public static String innerAction(String x) { return x; }
    }
}
