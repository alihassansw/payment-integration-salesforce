@isTest
private class BillingChargeAutomationTest {
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

  @testSetup
  static void setupTestData() {
    List<Account> accountsToInsert = new List<Account>();
    List<AcctSeed__Billing__c> billingsToInsert = new List<AcctSeed__Billing__c>();

    // create test records
    for (Integer i = 0; i < 5; i++) {
      accountsToInsert.add(
        new Account(Name = 'Test Account ' + i, Latest_Credit_Card_Token__c = String.valueOf(i + i + i))
      );
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
  static void testRetrievePastDuePayments() {
    List<AcctSeed__Billing__c> testData = new List<AcctSeed__Billing__c>();

    insert testData;

    List<AcctSeed__Billing__c> result = BillingChargeAutomation.retrievePastDuePayments();

    System.assertEquals(testData.size(), result.size(), 'Incorrect number of past due payments');

    for (AcctSeed__Billing__c billing : result) {
      System.assert(billing.Actual_Balance__c > 0);
      System.assertEquals('Renewal', billing.Subscription_Type__c);
      System.assertNotEquals('Inactive', billing.RB_Status__c);
    }
  }
    
  @isTest
  static void testProcessTransaction_Failed() {
    AcctSeed__Billing__c billingWithToken = [
      SELECT Id, AcctSeed__Customer__c, AcctSeed__Customer__r.Name, AcctSeed__Customer__r.Latest_Credit_Card_Token__c
      FROM AcctSeed__Billing__c
      WHERE AcctSeed__Customer__r.Name = 'Test Account 1'
    ];

    // Set up mock response for fetchPaymentMethodId
    String paymentMethodResponse = '{ "data": { "idFromLegacyId": "paymentMethodId123" } }';
    setupMockHttpResponse(paymentMethodResponse, 200);

    // Set up mock response for checkTransactionStatus
    String errorResponse = '{ "errors": [ { "message": "Unknown or expired single-use payment method.", "locations": [ { "line": 2, "column": 3 } ], "path": [ "chargePaymentMethod" ], "extensions": { "errorClass": "VALIDATION", "errorType": "user_error", "inputPath": [ "input", "paymentMethodId" ], "legacyCode": "91565" } } ], "data": { "chargePaymentMethod": null }, "extensions": { "requestId": "2f6b3792-e748-4622-aa22-5c421ba4514f" } }';
    setupMockHttpResponse(errorResponse, 200);

    Test.startTest();
    String result = BillingChargeAutomation.processTransaction(
      billingWithToken.AcctSeed__Customer__c,
      '100',
      billingWithToken.Id
    );
    Test.stopTest();
  }

  @isTest
  static void testProcessTransaction_SuccessfulTransaction() {
    AcctSeed__Billing__c billingWithToken = [
      SELECT Id, AcctSeed__Customer__c, AcctSeed__Customer__r.Name, AcctSeed__Customer__r.Latest_Credit_Card_Token__c
      FROM AcctSeed__Billing__c
      WHERE AcctSeed__Customer__r.Name = 'Test Account 1'
    ];

    // Set up mock response for fetchPaymentMethodId
    String paymentMethodResponse = '{ "data": { "idFromLegacyId": "paymentMethodId123" } }';
    setupMockHttpResponse(paymentMethodResponse, 200);

    // Set up mock response for checkTransactionStatus
    String transactionStatusResponse = '{ "data": { "chargePaymentMethod": { "transaction": { "id": "dummyId", "legacyId": "legacy123", "status": "SUCCESS", "processorResponse": { "message": "abc", "legacyCode": "123" } } } }, "idFromLegacyId": { "requestId": "123" } }';
    setupMockHttpResponse(transactionStatusResponse, 200);

    Test.startTest();
    String result = BillingChargeAutomation.processTransaction(
      billingWithToken.AcctSeed__Customer__c,
      '100',
      billingWithToken.Id
    );
    Test.stopTest();
  }

  @isTest
  static void testProcessTransaction_NoToken() {
    AcctSeed__Billing__c billingWithToken = [
      SELECT Id, AcctSeed__Customer__c, AcctSeed__Customer__r.Name, AcctSeed__Customer__r.Latest_Credit_Card_Token__c
      FROM AcctSeed__Billing__c
      WHERE AcctSeed__Customer__r.Name = 'Test Account 0'
    ];

    Test.startTest();
    String result = BillingChargeAutomation.processTransaction(
      billingWithToken.AcctSeed__Customer__c,
      '100',
      billingWithToken.Id
    );
    Test.stopTest();
  }
    
  @isTest
  static void testCheckTransactionStatus_SuccessResponse() {
    String responseBody = '{ "errors": [ { "message": "An object with this ID was not found." } ] }';
    setupMockHttpResponse(responseBody, 200);

    Test.startTest();
    ApiData data = BillingChargeAutomation.fetchPaymentMethodId('123');
    Test.stopTest();
  }

  @isTest
  static void testCheckTransactionStatus_ErrorResponse() {
    String errorResponse = '{ "errors": [ { "message": "Unknown or expired single-use payment method.", "locations": [ { "line": 2, "column": 3 } ], "path": [ "chargePaymentMethod" ], "extensions": { "errorClass": "VALIDATION", "errorType": "user_error", "inputPath": [ "input", "paymentMethodId" ], "legacyCode": "91565" } } ], "data": { "chargePaymentMethod": null }, "extensions": { "requestId": "2f6b3792-e748-4622-aa22-5c421ba4514f" } }';
    setupMockHttpResponse(errorResponse, 200);

    Test.startTest();
    ApiData data = BillingChargeAutomation.checkTransactionStatus('invalidPaymentMethodId', '50.00');
    Test.stopTest();

    System.assertEquals(true, data.hasErrorApiMessage);
    System.assertEquals('Unknown or expired single-use payment method.', data.errorApiMessage);
    System.assertEquals(200, data.apiStatusCode);
  }
    
  @isTest
  public static void testAddApiChargeAttempt() {
    
    AcctSeed__Billing__c testBillingRecord = [SELECT Id, Charge_attempts__c, Latest_Charge_Response__c, Payment_Processor_Response__c, Payment_Status__c
                                               FROM AcctSeed__Billing__c
                                               LIMIT 1];

    System.assertNotEquals(null, testBillingRecord, 'No test billing record found');
    BillingChargeAutomation.addApiChargeAttempt(testBillingRecord.Id, 'Test Error Message');

    AcctSeed__Billing__c updatedBillingRecord = [SELECT Id, Charge_attempts__c, Latest_Charge_Response__c, Payment_Processor_Response__c, Payment_Status__c
                                                  FROM AcctSeed__Billing__c
                                                  WHERE Id = :testBillingRecord.Id
                                                  LIMIT 1];

    System.assertNotEquals(null, updatedBillingRecord, 'Updated billing record not found');
    System.assertEquals(1, updatedBillingRecord.Charge_attempts__c, 'Charge attempts not updated correctly');
    System.assertEquals('Test Error Message', updatedBillingRecord.Payment_Processor_Response__c, 'Error message not updated correctly');
    System.assertEquals('Unsuccessful', updatedBillingRecord.Payment_Status__c, 'Payment status not updated correctly');
  }
    
  @isTest
  public static void wrongApiCall() {
      try {
          BillingChargeAutomation.makeApiCall('requestPayload');
          //BillingChargeAutomation.processTransaction('accountId', 'amount', 'billingId');
      } catch (Exception e) {}
  }
}