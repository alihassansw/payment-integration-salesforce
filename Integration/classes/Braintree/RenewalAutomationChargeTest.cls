@isTest
public class RenewalAutomationChargeTest {
  @testSetup
  static void setupTestData() {
    // Create test accounts
    List<Account> accountsToInsert = new List<Account>();
    for (Integer i = 0; i < 5; i++) {
      accountsToInsert.add(
        new Account(Name = 'Test Account ' + i, Latest_Credit_Card_Token__c = String.valueOf(i + i + i))
      );
    }
    insert accountsToInsert;

    // Create related records dynamically
    List<AcctSeed__Billing__c> billingsToInsert = new List<AcctSeed__Billing__c>();
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
      AcctSeed__Billing__c billing = new AcctSeed__Billing__c(
        AcctSeed__Customer__c = acc.Id,
        AcctSeed__Ledger__c = ledger.Id,
        AcctSeed__Accounting_Period__c = accountingPeriod.Id,
        AcctSeed__Billing_Format__c = billingFormat.Id
      );
      billingsToInsert.add(billing);
    }
    insert billingsToInsert;
  }

  @isTest
  static void test_retrieveRenewalPayments() {
    // Generate dynamic test data
    List<AcctSeed__Billing__c> testData = new List<AcctSeed__Billing__c>();
    insert testData;

    // Test the retrieveRenewalPayments method
    Test.startTest();
    List<AcctSeed__Billing__c> result = RenewalAutomationCharge.retrieveRenewalPayments();
    Test.stopTest();

    // Add assertions for the expected result
    // System.assertEquals(0, result.size());
  }

  @isTest
  static void test_processGoCardlessTransaction_Success() {
    // Generate dynamic test data
    String requestBody = '{ "payments": { "id": "PM008A08VT19Z1", "amount": 5000, "status": "pending_submission" } }';

    AcctSeed__Billing__c billingRecord = getTestBillingRecord();
    setupMockHttpResponse(requestBody, 201);

    // Test the processGoCardlessTransaction method
    Test.startTest();
    String result = RenewalAutomationCharge.processGoCardlessTransaction(
      requestBody,
      billingRecord.Id,
      billingRecord.AcctSeed__Customer__c
    );
    Test.stopTest();

    // Add assertions for the expected result
    // System.assertEquals('Expected Result', result);
  }

  @isTest
  static void test_processGoCardlessTransaction_Failed() {
    // Generate dynamic test data
    String requestBody = '{ "error": { "message": "abc", "errors": [ { "reason": "abc", "field": "currency", "message": "abc" } ] } }';

    AcctSeed__Billing__c billingRecord = getTestBillingRecord();
    setupMockHttpResponse(requestBody, 200);

    // Test the processGoCardlessTransaction method
    Test.startTest();
    String result = RenewalAutomationCharge.processGoCardlessTransaction(
      requestBody,
      billingRecord.Id,
      billingRecord.AcctSeed__Customer__c
    );
    Test.stopTest();

    // Add assertions for the expected result
    // System.assertEquals('Expected Result', result);
  }

  @isTest
  static void test_processTransaction() {
    // Generate dynamic test data
    String currentToken = 'xyz';
    AcctSeed__Billing__c billingRecord = getTestBillingRecord();
    String amount = '1000';
    String paymentMethodResponse = '{ "data": { "idFromLegacyId": "paymentMethodId123" } }';
    setupMockHttpResponse(paymentMethodResponse, 200);

    // Set up mock response for checkTransactionStatus
    String transactionStatusResponse = '{ "data": { "chargePaymentMethod": { "transaction": { "id": "dummyId", "legacyId": "legacy123", "status": "SUBMITTED_FOR_SETTLEMENT", "processorResponse": { "message": "abc", "legacyCode": "123" } } } }, "idFromLegacyId": { "requestId": "123" } }';
    setupMockHttpResponse(transactionStatusResponse, 200);

    // Test the processTransaction method
    Test.startTest();
    String result = RenewalAutomationCharge.processTransaction(
      currentToken,
      amount,
      billingRecord.AcctSeed__Customer__c,
      billingRecord.Id
    );
    Test.stopTest();

    // Add assertions for the expected result
    // System.assertEquals('Expected Result', result);
  }
  
  @isTest
  static void testNoPaymentMethodId() {
    // Generate dynamic test data
    String currentToken = 'xyz';
    AcctSeed__Billing__c billingRecord = getTestBillingRecord();
    String amount = '1000';
    String paymentMethodResponse = '{ "errors": [ { "message": "Unknown or expired single-use payment method." } ] }';
    setupMockHttpResponse(paymentMethodResponse, 200);

    // Test the processTransaction method
    Test.startTest();
    String result = RenewalAutomationCharge.processTransaction(
      currentToken,
      amount,
      billingRecord.AcctSeed__Customer__c,
      billingRecord.Id
    );
    Test.stopTest();

    // Add assertions for the expected result
    // System.assertEquals('Expected Result', result);
  }
    
  @isTest
  static void testUnsuccessfulTransaction() {
	// Generate dynamic test data
    String currentToken = 'xyz';
    AcctSeed__Billing__c billingRecord = getTestBillingRecord();
    String amount = '1000';
    String paymentMethodResponse = '{ "data": { "idFromLegacyId": "paymentMethodId123" } }';
    setupMockHttpResponse(paymentMethodResponse, 200);

    // Set up mock response for checkTransactionStatus
    String transactionStatusResponse = '{ "data": { "chargePaymentMethod": { "transaction": { "id": "dummyId", "legacyId": "legacy123", "status": "DECLINED", "processorResponse": { "message": "abc", "legacyCode": "123" } } } }, "idFromLegacyId": { "requestId": "123" } }';
    setupMockHttpResponse(transactionStatusResponse, 200);

    // Test the processTransaction method
    Test.startTest();
    String result = RenewalAutomationCharge.processTransaction(
      currentToken,
      amount,
      billingRecord.AcctSeed__Customer__c,
      billingRecord.Id
    );
    Test.stopTest();
  }

  @isTest
  static void processGoCardlessTransaction_ScriptThrownErrors() {
    // Generate dynamic test data
    String requestBody = '{ "payments": { "id": "PM008A08VT19Z1", "amount": 5000, "status": "pending_submission" } }';
    AcctSeed__Billing__c billingRecord = getTestBillingRecord();
    setupMockHttpResponse(requestBody, 201);

    // Test the processGoCardlessTransaction method with a script thrown error
    Test.startTest();
    try {
      RenewalAutomationCharge.processGoCardlessTransaction(
        'requestBody',
        'billingRecord.Id',
        'billingRecord.AcctSeed__Customer__c'
      );
      // Add assertions for expected script thrown errors here, if needed
      //System.assert(false, 'Expected script thrown error not thrown');
    } catch (Exception e) {
      // Add assertions for the expected exception message, if needed
      //System.assertEquals('Expected Exception Message', e.getMessage());
    }
    Test.stopTest();
  }

  @isTest
  static void handleSuccessfulTransaction_ScriptThrownErrors() {
    // Generate dynamic test data
    String requestBody = '{ "payments": { "id": "PM008A08VT19Z1" } }';
    AcctSeed__Billing__c billingRecord = getTestBillingRecord();
    setupMockHttpResponse(requestBody, 201);

    // Test the processGoCardlessTransaction method with a script thrown error
    Test.startTest();
    try {
      RenewalAutomationCharge.processGoCardlessTransaction(
        requestBody,
        billingRecord.Id,
        billingRecord.AcctSeed__Customer__c
      );
      // Add assertions for expected script thrown errors here, if needed
      //System.assert(false, 'Expected script thrown error not thrown');
    } catch (Exception e) {
      // Add assertions for the expected exception message, if needed
      //System.assertEquals('Expected Exception Message', e.getMessage());
    }
    Test.stopTest();
  }
    
  @isTest
  static void test_processTransaction_ScriptThrownErrors() {
    AcctSeed__Billing__c billingRecord = getTestBillingRecord();
      
    try {
        RenewalAutomationCharge.processTransaction(
            'xyz',
            '1000',
            'accountId',
            'billingId'
    	);
    } catch (Exception e) {}
  }

  // Helper method to retrieve a test billing record
  static AcctSeed__Billing__c getTestBillingRecord() {
    return [
      SELECT Id, AcctSeed__Customer__c
      FROM AcctSeed__Billing__c
      WHERE AcctSeed__Customer__r.Name = 'Test Account 1'
      LIMIT 1
    ];
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