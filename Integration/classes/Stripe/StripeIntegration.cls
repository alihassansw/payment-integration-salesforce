public class StripeIntegration {
  public static final String BASE_URL = 'https://api.stripe.com';
  public static final String SECRET_API_KEY = 'sk_test_51NZu40Agww1gW1XKGPD9gpstxiHJdsk91PtKXXjCZH1enXay2Yx6EPJi0ZuSP7V7hWJSnbOUceSlo6KP39E0cvyo00rKriKehK'; 
  // sk_live_4sTZNpgsfWsYqufYxNkzMHCx : sk_test_51NZu40Agww1gW1XKGPD9gpstxiHJdsk91PtKXXjCZH1enXay2Yx6EPJi0ZuSP7V7hWJSnbOUceSlo6KP39E0cvyo00rKriKehK

  public static HttpResponse makeApiCall(String requestBody, String endpoint) {
    try {
      HttpRequest apiRequest = new HttpRequest();
      apiRequest.setMethod('POST');
      apiRequest.setEndpoint(endpoint);
      apiRequest.setHeader('Authorization', 'Bearer ' + SECRET_API_KEY);
      apiRequest.setHeader('Content-Type', 'application/x-www-form-urlencoded');
      apiRequest.setHeader('Accept', 'application.json');
      apiRequest.setBody(requestBody);
      Http http = new Http();
      HttpResponse apiResponse = http.send(apiRequest);
      return apiResponse;
    } catch (Exception e) {
      System.debug('An Error Occurred: ' + e.getMessage());
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled
  public static String processStripeTransaction(
    String amount,
    String currencyType,
    String customerId,
    String billingId,
    String accountId
  ) {
    String endpoint = BASE_URL + '/v1/charges';
    String requestBody = 'amount=' + amount + '&currency=' + currencyType + '&customer=' + customerId;
    try {
      HttpResponse res = makeApiCall(requestBody, endpoint);
      String responseBody = res.getBody();
      Map<String, Object> jsonData = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
      System.debug('jsonData: ' + jsonData);
      if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
        handleSuccessfulTransaction(jsonData, billingId, accountId);
      } else {
        handleFailedTransaction(jsonData, billingId, accountId);
      }
      return responseBody;
    } catch (Exception e) {
      System.debug('An error occurred: ' + e.getMessage());
      throw new AuraHandledException(e.getMessage());
    }
  }

  public static void handleFailedTransaction(Map<String, Object> jsonData, String billingId, String accountId) {
    Map<String, Object> errorObject = (Map<String, Object>) jsonData.get('error');
    String errorCode = (String) errorObject.get('code');
    String errorParam = (String) errorObject.get('param');
    String errorMessage = (String) errorObject.get('message');

    System.debug('Error Code: ' + errorCode);
    System.debug('Error Param: ' + errorParam);
    System.debug('Error Message: ' + errorMessage);
    BillingChargeAutomation.addApiChargeAttempt(billingId, errorMessage);
  }

  public static void handleSuccessfulTransaction(Map<String, Object> jsonData, String billingId, String accountId) {
    String transactionId = (String) jsonData.get('id');
    Integer amountSubstring = (Integer) jsonData.get('amount');
    String amountExtracted = String.valueOf(amountSubstring).substring(0, String.valueOf(amountSubstring).length() - 2);

    Boolean handleRecords = BillingChargeAutomation.updateBillingOnSuccessfulTransaction(
      billingId,
      accountId,
      amountExtracted,
      transactionId, 'stripe'
    );
    if (handleRecords) {
      System.debug('All Good');
    } else {
      System.debug('record handling failed');
    }
  }
}