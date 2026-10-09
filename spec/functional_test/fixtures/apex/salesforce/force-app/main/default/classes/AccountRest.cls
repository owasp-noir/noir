// Not a route: @RestResource(urlMapping='/Commented/*')
@RestResource(urlMapping='/Account/*')
global with sharing class AccountRest {
    @HttpGet
    global static Account doGet() {
        RestRequest req = RestContext.request;
        String accountId = req.params.get('id');
        String fields = RestContext.request.params.get('fields');
        String trace = req.headers.get('X-Trace-Id');
        return [SELECT Id, Name FROM Account WHERE Id = :accountId];
    }

    @HttpPost
    global static String doPost(String name, String phone) {
        Account a = new Account(Name = name, Phone = phone);
        insert a;
        return a.Id;
    }

    @HttpDelete
    global static void doDelete() {
        String id = RestContext.request.requestURI.substringAfterLast('/');
        delete [SELECT Id FROM Account WHERE Id = :id];
    }

    /* @HttpPut
    global static void doPut(String ignored) {} */

    // Not static: Apex REST ignores it.
    global String helper(String x) { return '{'; }
}
