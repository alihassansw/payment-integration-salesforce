public with sharing class RenewalAutomationCharge {
  @AuraEnabled
  public static List<AcctSeed__Billing__c> retrieveRenewalPayments() {
    List<AcctSeed__Billing__c> renewalPayments = [
      SELECT
        Id,
        Name,
        Mandate_Id__c,
        Charge_date__c,
        X1stDayofMonth__c,
        AcctSeed__Date__c,
        Payment_Status__c,
        Payment_Gateway__c,
        AcctSeed__Total__c,
        AcctSeed__Status__c,
        Subscription_Type__c,
        AcctSeed__Balance__c,
        AcctSeed__Customer__c,
        Subscription_Status__c,
        AcctSeed__Customer__r.Name,
        Payment_Processor_Response__c,
        AcctSeed__Customer__r.Latest_Credit_Card_Token__c,
        AcctSeed__Customer__r.AcctSeed__Stripe_Customer_Id__c
      FROM AcctSeed__Billing__c
      WHERE
        Subscription_Type__c = 'Renewal'
        AND AcctSeed__Balance__c != 0
        // AND Payment_id__c = NULL
        // AND AcctSeed__Date__c = 2023-06-01
        // AND AcctSeed__Status__c NOT IN ('In Process', 'Approved')
        // AND Subscription_Status__c = 'Active'
        AND AcctSeed__Customer__r.Exclude_from_PD_automation__c = FALSE
        AND AcctSeed__Customer__r.Has_Pending_Cancellation__c = FALSE
    ];
    return renewalPayments;
  }

  @AuraEnabled
  public static String processGoCardlessTransaction(String requestBody, String billingId, String accountId) {
    String endpoint = GoCardlessRequest.baseURL + '/payments';

    try {
      HttpResponse res = GoCardlessRequest.callAPI('POST', endpoint, requestBody, null);
      String responseBody = res.getBody();
      Map<String, Object> jsonData = (Map<String, Object>) JSON.deserializeUntyped(responseBody);

      System.debug('jsonData: ' + jsonData);

      if (res.getStatusCode() == 201) {
        handleSuccessfulTransaction(jsonData, billingId, accountId);
      } else {
        handleFailedTransaction(jsonData, billingId);
      }

      return responseBody;
    } catch (Exception e) {
      System.debug('An error occurred: ' + e.getMessage());
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled
  public static String processTransaction(String currentToken, String amount, String accountId, String billingId) {
    try {
      String formattedTransactionAmount = amount;
      ApiData transactionData;

      if (currentToken.startsWith('cGF5')) {
        transactionData = BillingChargeAutomation.checkTransactionStatus(currentToken, formattedTransactionAmount);
      } 
      
      else {
        ApiData paymentMethodData = BillingChargeAutomation.fetchPaymentMethodId(currentToken);

        if (!paymentMethodData.hasPaymentMethodId) {
          return paymentMethodData.apiResponse;
        }

        String selectedPaymentMethodId = paymentMethodData.paymentMethodId;
        transactionData = BillingChargeAutomation.checkTransactionStatus(selectedPaymentMethodId, formattedTransactionAmount);
      }


      if (transactionData.transactionStatus == 'SUBMITTED_FOR_SETTLEMENT') {
        BillingChargeAutomation.updateBillingOnSuccessfulTransaction(
          billingId,
          accountId,
          amount,
          transactionData.transactionId,
          'braintree'
        );
      } 
      
      else {
        BillingChargeAutomation.addApiChargeAttempt(billingId, transactionData.processorResponseMessage);
      }

      return transactionData.apiResponse;
    } catch (Exception e) {
      System.debug('Error occurred while processing transaction: ' + e.getMessage());
      throw new AuraHandledException(e.getMessage());
    }
  }

  public static void handleSuccessfulTransaction(Map<String, Object> jsonData, String billingId, String accountId) {
    try {
      Map<String, Object> payments = (Map<String, Object>) jsonData.get('payments');
      String transactionId = (String) payments.get('id');
      Integer amountSubstring = (Integer) payments.get('amount');
      String amountExtracted = String.valueOf(amountSubstring)
        .substring(0, String.valueOf(amountSubstring).length() - 2);
      String status = (String) payments.get('status');

      AcctSeed__Billing__c billingRecord = new AcctSeed__Billing__c(
        Id = billingId,
        Payment_id__c = transactionId,
        API_charge__c = true,
        Payment_Status__c = 'Pending'
      );

      update billingRecord;
    } catch (Exception e) {
      System.debug('An Error Occurred while hanlding transaction result: ' + e.getMessage());
      throw new AuraHandledException(e.getMessage());
    }
  }

  public static void handleFailedTransaction(Map<String, Object> jsonData, String billingId) {
    Map<String, Object> error = (Map<String, Object>) jsonData.get('error');
    List<Object> errors = (List<Object>) error.get('errors');
    Map<String, Object> errorEntry = (Map<String, Object>) errors[0];
    String reason = (String) errorEntry.get('reason');
    String field = (String) errorEntry.get('field');
    String errorMessage = (String) errorEntry.get('message');

    BillingChargeAutomation.addApiChargeAttempt(billingId, errorMessage);
  }
}