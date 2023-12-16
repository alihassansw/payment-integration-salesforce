@isTest
public class StripeIntegrationTest {
  @testSetup
  static void setupTestData() {
    List<Account> accountsToInsert = new List<Account>();
    List<AcctSeed__Billing__c> billingsToInsert = new List<AcctSeed__Billing__c>();

    // create test records
    for (Integer i = 0; i < 5; i++) {
      accountsToInsert.add(new Account(Name = 'Test Account ' + i, Latest_Credit_Card_Token__c = String.valueOf(i + i + i)));
    }

    insert accountsToInsert;

    Account account = [SELECT Id, Name FROM Account WHERE Name = 'Test Account 1'];
    CC_Token__c token = new CC_Token__c(Associated_Account__c = account.Id, Token__c = '123', GraphQL_Token__c = '123');

    insert token;

    AcctSeed__Billing_Format__c billingFormat = new AcctSeed__Billing_Format__c(
      Name = 'Test Pdf',
      AcctSeed__Type__c = 'Activity Statement',
      AcctSeed__Default_Email_Template__c = 'Activity_Statement_Email_Template',
      AcctSeed__Visualforce_PDF_Page__c = 'BillingActivityStmtModernPDF'
    );

    insert billingFormat;

    AcctSeed__GL_Account__c GLAccount = new AcctSeed__GL_Account__c(
      Name = 'Test Account',
      AcctSeed__Sub_Type_1__c = 'Assets',
      AcctSeed__Bank__c = true
    );

    insert GLAccount;

    AcctSeed__Accounting_Period__c accountingPeriod = new AcctSeed__Accounting_Period__c(
      Name = '2023-06',
      AcctSeed__Start_Date__c = Date.today(),
      AcctSeed__End_Date__c = Date.today().addYears(5)
    );

    insert accountingPeriod;

    AcctSeed__Ledger__c ledger = new AcctSeed__Ledger__c(
      Name = 'Test Ledger',
      AcctSeed__Type__c = 'Transactional',
      AcctSeed__Default_Bank_Account__c = GLAccount.Id,
      AcctSeed__Default_Billing_Format__c = billingFormat.Id,
      AcctSeed__Billing_Activity_Statement_Format__c = billingFormat.Id,
      AcctSeed__Billing_Outstanding_Statement_Format__c = billingFormat.Id
    );

    insert ledger;

    for (Account acc : accountsToInsert) {
      AcctSeed__Billing__c billing = new AcctSeed__Billing__c();
      billing.AcctSeed__Customer__c = acc.Id;
      billing.AcctSeed__Ledger__c = ledger.Id;
      billing.AcctSeed__Accounting_Period__c = accountingPeriod.Id;
      billing.AcctSeed__Billing_Format__c = billingFormat.Id;
      billingsToInsert.add(billing);
    }

    insert billingsToInsert;
  }

  @isTest
  static void processStripeTransaction() {
    AcctSeed__Billing__c billing = [
      SELECT Id, AcctSeed__Customer__c, AcctSeed__Customer__r.Name, AcctSeed__Customer__r.Latest_Credit_Card_Token__c
      FROM AcctSeed__Billing__c
      WHERE AcctSeed__Customer__r.Name = 'Test Account 1'
    ];
    String requestBody = '{"id": "ch_3NbIFWAgww1gW1XK1TQmjzV5","amount": 1000}';
    setupMockHttpResponse(requestBody, 200);
    Test.startTest();
    String result = StripeIntegration.processStripeTransaction('1000', 'usd', '123', billing.Id, billing.AcctSeed__Customer__c);
    Test.stopTest();
  }

  @isTest
  static void processStripeTransaction_failed() {
    AcctSeed__Billing__c billing = [
      SELECT Id, AcctSeed__Customer__c, AcctSeed__Customer__r.Name, AcctSeed__Customer__r.Latest_Credit_Card_Token__c
      FROM AcctSeed__Billing__c
      WHERE AcctSeed__Customer__r.Name = 'Test Account 1'
    ];
    String requestBody = '{"error": {"code": "xxxxxxxx","message": "xxxxxxxxxxx","param":"xxxxxxxxx"}}';
    setupMockHttpResponse(requestBody, 404);
    Test.startTest();
    String result = StripeIntegration.processStripeTransaction('1000', 'usd', '123', billing.Id, billing.AcctSeed__Customer__c);
    Test.stopTest();
  }

  @isTest
  static void processStripeTransaction_ScriptError() {
    try {
      StripeIntegration.processStripeTransaction('1000', 'usd', '123', 'billing.Id', 'billing.AcctSeed__Customer__c');
    } catch (Exception e) {
    }
  }

  @isTest
  public static void wrongApiCall() {
    try {
      StripeIntegration.makeApiCall('requestPayload', '');
    } catch (Exception e) {
    }
  }

  private class MockHttpResponse implements HttpCalloutMock {
    HttpResponse response;
    MockHttpResponse(HttpResponse response) {
      this.response = response;
    }
    public HttpResponse respond(HttpRequest request) {
      return response;
    }
  }

  private static void setupMockHttpResponse(String responseBody, Integer statusCode) {
    HttpResponse response = new HttpResponse();
    response.setStatusCode(statusCode);
    response.setBody(responseBody);
    Test.setMock(HttpCalloutMock.class, new MockHttpResponse(response));
  }
}