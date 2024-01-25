/*
********************************************************
@Class Name     : BillingChargeAutomation
@written by     : Ali Hassan 
@description    : Braintree Integration
@param          :
@return         : Output
********************************************************
*/

/***************************		Change credentials and ids before deployment			**********************************************/

public with sharing class BillingChargeAutomation {
  // Constants
  public static final String ENDPOINT = '';
  public static final String BRAINTREE_VERSION = '';
  public static String bankAccount = '';
  public static String creditGlAccount = '';
  public static String ledgerAccount = '';
  public static String accountingPeriod = '';
  public static String generalLedgerAccount = '';
  public static String adjustmentGlAccount = '';
  public static String adjustmentAmount = '';
  public static String bankAccountGoCardless = '';

  @AuraEnabled
  public static List<AcctSeed__Billing__c> retrievePastDuePayments() {
    List<AcctSeed__Billing__c> pastDuePayments = [
      SELECT
        Id,
        Name,
        Actual_Balance__c,
        AcctSeed__Date__c,
        AcctSeed__Customer__c,
        AcctSeed__Customer__r.Name,
        AcctSeed__Status__c,
        Days_Past_Due__c,
        AcctSeed__Customer__r.Latest_Credit_Card_Token__c
      FROM AcctSeed__Billing__c
      WHERE
        Actual_Balance__c > 0
        AND Subscription_Type__c = 'Renewal'
        AND RB_Status__c != 'Inactive'
        AND AcctSeed__Customer__r.Has_Pending_Cancellation__c = FALSE
        AND (NOT (Account_Name__c LIKE '%NexGenEsis Healthcare (Parent)%'
        OR Account_Name__c LIKE '%Los Angeles Liposuction Centers%'))
        AND AcctSeed__Status__c NOT IN ('In Process', 'Approved')
        AND AcctSeed__Customer__r.Exclude_from_PD_automation__c = FALSE
        AND Days_Past_Due__c <= 30
        AND (NOT (Account_Name__c LIKE '%Sample%'
        OR Account_Name__c LIKE '%TEST%'))
        AND Revenue_Event__c = 'Standard Renewal'
        AND Days_Past_Due__c > 1
    ];
    return pastDuePayments;
  }

  @AuraEnabled
  public static String processTransaction(String accountId, String amount, String billingId) {
    Boolean isSuccessTransaction = false;
    Boolean hasAnyTransactionSuccess = false;
    String formattedTransactionAmount = amount + '.00';
    String selectedPaymentMethodId = '';
    try {
      List<CC_Token__c> accountPaymentDataList = retrievePaymentData(accountId);

      if (accountPaymentDataList.isEmpty()) {
        return 'No CC Token on file';
      }

      for (CC_Token__c paymentData : accountPaymentDataList) {
        String currentToken = paymentData.Token__c;

        if (isSuccessTransaction) {
          break;
        }
        ApiData paymentMethodData = fetchPaymentMethodId(currentToken);
        if (paymentMethodData.hasPaymentMethodId) {
          selectedPaymentMethodId = paymentMethodData.paymentMethodId;

          ApiData transactionData = checkTransactionStatus(selectedPaymentMethodId, formattedTransactionAmount);
          System.debug('ApiData: ' + transactionData);

          if (transactionData.hasTransactionId) {
            Boolean x = updateBillingOnSuccessfulTransaction(
              billingId,
              accountId,
              amount,
              transactionData.transactionId,
              'braintree'
            );

            isSuccessTransaction = true;
            hasAnyTransactionSuccess = true;

            return transactionData.apiResponse;
          } else if (transactionData.hasErrorApiMessage) {
            System.debug('API Error: ' + transactionData.errorApiMessage);
            System.debug('record handling failed');
            return transactionData.apiResponse;
          }
        } else if (!paymentMethodData.hasPaymentMethodId) {
          return paymentMethodData.errorApiMessage;
        }
      }
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
    return null;
  }

  public static ApiData checkTransactionStatus(String selectedPaymentMethodId, String formattedTransactionAmount) {
    String requestPayload =
      '{' +
      '"query": "mutation ($input: ChargePaymentMethodInput!) { chargePaymentMethod(input: $input) { transaction { id status legacyId processorResponse { message legacyCode }}}}",' +
      '"variables": {' +
      '"input": {' +
      '"paymentMethodId": "' +
      selectedPaymentMethodId +
      '",' +
      '"transaction": {' +
      '"amount": ' +
      formattedTransactionAmount +
      '}' +
      '}' +
      '}' +
      '}';

    HttpResponse apiResponse = makeApiCall(requestPayload);
    String apiResponseBody = apiResponse.getBody();
    Map<String, Object> apiJsonResponse = (Map<String, Object>) JSON.deserializeUntyped(apiResponseBody);

    ApiData data = new ApiData();

    if (apiResponseBody.contains('id') && apiResponseBody.contains('status')) {
      Map<String, Object> dataMap = (Map<String, Object>) apiJsonResponse.get('data');
      Map<String, Object> chargePaymentMethodMap = (Map<String, Object>) dataMap.get('chargePaymentMethod');
      Map<String, Object> transactionMap = (Map<String, Object>) chargePaymentMethodMap.get('transaction');
      Map<String, Object> processorResponseMap = (Map<String, Object>) transactionMap.get('processorResponse');

      String id = (String) transactionMap.get('id');
      String legacyId = (String) transactionMap.get('legacyId');
      String status = (String) transactionMap.get('status');
      String processorMessage = (String) processorResponseMap.get('message');
      String legacyCode = (String) processorResponseMap.get('legacyCode');

      data.hasTransactionId = true;
      data.transactionId = legacyId;
      data.transactionStatus = status;
      data.processorResponseMessage = processorMessage;
      data.processorResponseCode = legacyCode;
    } else if (apiResponseBody.contains('errors')) {
      String apiErrorMessage = (String) ((Map<String, Object>) ((List<Object>) apiJsonResponse.get('errors')).get(0))
        .get('message');

      data.hasErrorApiMessage = true;
      data.errorApiMessage = apiErrorMessage;
    }
    data.apiResponse = apiResponseBody;
    data.apiStatusCode = apiResponse.getStatusCode();

    return data;
  }

  public static List<sObject> retrievePaymentData(String accountId) {
    return [
      SELECT Token__c, GraphQL_Token__c
      FROM CC_Token__c
      WHERE Deactivate_Token__c = FALSE AND Associated_Account__c = :accountId
    ];
  }

  public static ApiData fetchPaymentMethodId(String token) {
    String requestPayload =
      '{ "query": "query PaymentMethod { idFromLegacyId(legacyId: \\"' +
      token +
      '\\", type: PAYMENT_METHOD) }" }';

    HttpResponse apiResponse = makeApiCall(requestPayload);
    String apiResponseBody = apiResponse.getBody();
    Map<String, Object> apiJsonResponse = (Map<String, Object>) JSON.deserializeUntyped(apiResponse.getBody());

    ApiData newData = new ApiData();

    if (apiResponseBody.contains('idFromLegacyId')) {
      Map<String, Object> responseData = (Map<String, Object>) apiJsonResponse.get('data');
      String paymentMethodId = (String) responseData.get('idFromLegacyId');
      newData.paymentMethodId = paymentMethodId;
      newData.hasPaymentMethodId = true;
      return newData;
    } else {
      List<Object> errors = (List<Object>) apiJsonResponse.get('errors');
      Map<String, Object> firstError = (Map<String, Object>) errors[0];
      String errorMessage = (String) firstError.get('message');
      newData.hasPaymentMethodId = false;
      newData.errorApiMessage = errorMessage;
      return newData;
    }
  }

  public static Boolean updateBillingOnSuccessfulTransaction(
    String billingId,
    String accountId,
    String amount,
    String transactionId,
    String gateway
  ) {
    Savepoint sp; 
    Boolean isSuccess = false;
    Date today = Date.valueOf(Datetime.now().format('yyyy-MM-dd'));

    try {
      AcctSeed__Billing__c billingRecord = [
        SELECT Id, API_charge__c, Revenue_Event__c, PD_Collected_by__c
        FROM AcctSeed__Billing__c
        WHERE Id = :billingId
        LIMIT 1
      ];

      if (billingRecord != null) {
        // Update the billing record
        billingRecord.API_charge__c = true;
        billingRecord.Payment_Status__c = 'Successful';
        // billingRecord.PD_Collected_by__c = 'Finance Team';
        // billingRecord.Revenue_Event__c = 'Past Due Full Collections';
        update billingRecord;
        System.debug('Billing updated successfully: ' + billingRecord.Id);
      }

      sp = Database.setSavepoint();

      AcctSeed__Cash_Receipt__c cashReceipt = new AcctSeed__Cash_Receipt__c(
        AcctSeed__Ledger__c = ledgerAccount,
        AcctSeed__Amount__c = Decimal.valueOf(amount),
        AcctSeed__Account__c = accountId,
        AcctSeed__Receipt_Date__c = today,
        // AcctSeed__Bank_Account__c = (gateway == 'braintree') ? bankAccountBraintree : bankAccountStripe,
        AcctSeed__Bank_Account__c = bankAccount,
        AcctSeed__Payment_Reference__c = transactionId,
        AcctSeed__Credit_GL_Account__c = creditGlAccount,
        AcctSeed__Accounting_Period__c = accountingPeriod
      );

      Database.SaveResult insertCashReceipt = Database.insert(cashReceipt, false);

      Boolean isRecordCreated = insertCashReceipt.isSuccess();
      if (isRecordCreated) {
        System.debug('Cash Receipt created successfully: ' + insertCashReceipt.getId());

        AcctSeed__Billing_Cash_Receipt__c billingReceipt = new AcctSeed__Billing_Cash_Receipt__c(
          AcctSeed__Billing__c = billingId,
          AcctSeed__Applied_Date__c = today,
          AcctSeed__Cash_Receipt__c = insertCashReceipt.getId(),
          AcctSeed__Applied_Amount__c = Decimal.valueOf(amount),
          AcctSeed__Adjustment_Amount__c = Decimal.valueOf(adjustmentAmount),
          AcctSeed__Adjustment_GL_Account__c = generalLedgerAccount
        );

        Database.SaveResult insertBillingReceipt = Database.insert(billingReceipt, false);

        Boolean isBillingCreated = insertBillingReceipt.isSuccess();
        if (isBillingCreated) {
          System.debug('Billing Cash Receipt created successfully: ' + insertBillingReceipt.getId());
          isSuccess = true;
        } else {
          System.debug('Error occurred while inserting Billing Cash Receipt: ' + insertBillingReceipt.getErrors());
        }
      } else {
        System.debug('Error occurred while inserting Cash Receipt: ' + insertCashReceipt.getErrors());
      }
    } catch (Exception e) {
      System.debug('An error occurred: ' + e.getMessage());
    } finally {
      if (!isSuccess) {
        Database.rollback(sp);
      }
    }
    return isSuccess;
  }

  public static void addApiChargeAttempt(String billingId, String errorMessage) {
    Integer newChargeAttempts = 1;
    List<AcctSeed__Billing__c> billingsToUpdate = new List<AcctSeed__Billing__c>();
    List<AcctSeed__Billing__c> billingRecords = [
      SELECT Id, Charge_attempts__c, Latest_Charge_Response__c
      FROM AcctSeed__Billing__c
      WHERE Id = :billingId
      LIMIT 1
    ];

    for (AcctSeed__Billing__c billingRecord : billingRecords) {
      Decimal chargeAttempts = billingRecord.Charge_attempts__c;

      if (chargeAttempts == null || chargeAttempts == 0) {
        billingRecord.Charge_attempts__c = Decimal.valueOf(newChargeAttempts);
      } else {
        billingRecord.Charge_attempts__c = chargeAttempts + newChargeAttempts;
      }

      billingRecord.Payment_Processor_Response__c = errorMessage;
      billingRecord.Payment_Status__c = 'Unsuccessful';
      // billingRecord.Latest_Charge_Response__c = 'Processor Declined (2038)';
      billingsToUpdate.add(billingRecord);
    }

    List<Database.SaveResult> updateResults = Database.update(billingsToUpdate, false);

    if (!updateResults.isEmpty() && updateResults[0].isSuccess()) {
      System.debug('Attempt charge added on record: ' + updateResults[0].getId());
    } else {
      System.debug('Error occured when adding attempt charge on Billing: ' + updateResults[0].getErrors());
    }
  }

  public static HttpResponse makeApiCall(String requestPayload) {
    try {
      HttpRequest apiRequest = new HttpRequest();
      apiRequest.setMethod('POST');
      apiRequest.setEndpoint('callout:braintree');
      apiRequest.setHeader('Braintree-Version', BRAINTREE_VERSION);
      apiRequest.setHeader('Content-Type', 'application/json');
      apiRequest.setHeader('Accept', 'application/json');
      apiRequest.setBody(requestPayload);
      Http http = new Http();
      HttpResponse apiResponse = http.send(apiRequest);
      return apiResponse;
    } catch (Exception e) {
      System.debug('An Error Occurred: ' + e.getMessage());
      throw new AuraHandledException(e.getMessage());
    }
  }
}
