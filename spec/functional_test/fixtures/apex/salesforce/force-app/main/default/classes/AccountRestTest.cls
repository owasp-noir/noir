@isTest
private class AccountRestTest {
    @AuraEnabled
    public static void notAnAction(String x) {}

    @isTest static void testGet() {
        RestContext.request = new RestRequest();
        RestContext.request.params.put('id', '001');
        AccountRest.doGet();
    }
}
