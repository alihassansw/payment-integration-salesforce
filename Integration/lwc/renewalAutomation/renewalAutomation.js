import processGoCardlessTransaction from "@salesforce/apex/RenewalAutomationCharge.processGoCardlessTransaction";
import processTransaction from "@salesforce/apex/RenewalAutomationCharge.processTransaction";
import getApexData from "@salesforce/apex/RenewalAutomationCharge.retrieveRenewalPayments";
import processStripeTransaction from "@salesforce/apex/StripeIntegration.processStripeTransaction";
import LightningConfirm from "lightning/confirm";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { LightningElement, track } from "lwc";

export default class RenewalAutomation extends LightningElement {    
  @track data;
  @track error;
  @track columnsList = [
    //Customer: Account Name
    {
      label: "Customer: Account Name",
      fieldName: "accLink",
      type: "url",
      typeAttributes: { label: { fieldName: "AcctSeed__Customer_Name" }, target: "_blank" }
    },
    //Billing: Billing Number
    {
      label: "Billing: Billing Number",
      fieldName: "bcLink",
      type: "url",
      typeAttributes: { target: "_blank", label: { fieldName: "Name" } }
    },
    //Billing Date
    { label: "Billing Date", fieldName: "AcctSeed__Date__c", type: "date", typeAttributes: { timeZone: "GMT" } },
    //Subscription Type
    { label: "Subscription Type", fieldName: "Subscription_Type__c" },
    //"Total"
    { label: "Total", fieldName: "AcctSeed__Total__c", type: "currency", typeAttributes: { currencyCode: "USD" } },
    //"Balance"
    { label: "Balance", fieldName: "AcctSeed__Balance__c", type: "currency", typeAttributes: { currencyCode: "USD" } },
    //Payment Status
    { label: "Payment Status", fieldName: "Payment_Status__c" },
    //Payment Gateway
    { label: "Payment Gateway", fieldName: "Payment_Gateway__c" },
    //Payment Processor Response
    { label: "Payment Processor Response", fieldName: "Payment_Processor_Response__c" },
    //button
    {
      type: "button",
      typeAttributes: {
        label: "Run",
        name: "runAPI",
        title: "run action",
        disabled: false,
        value: "runAPI",
        class: "run-transation",
        iconName: "",
        variant: "brand"
      }
    }
  ];

  @track showSpinner = false; // Flag to control the visibility of a spinner

  // It is called when the component is inserted into the DOM
  async connectedCallback() {
    this.fetchData(null);
  }

  // Method to filter data based on user input
  async filterData(event) {
    const { value } = event.target;
    value === "All" ? await this.fetchData(null) : await this.fetchData(value);
  }

  // Method to map and preprocess data received from the server
  mapData(result) {
    return result.map((record) => ({
      ...record,
      AcctSeed__Customer_Name: record.AcctSeed__Customer__r.Name,
      AcctSeed__Stripe_Customer_Id__c: record.AcctSeed__Customer__r.AcctSeed__Stripe_Customer_Id__c,
      AcctSeed__Customer_Latest_Credit_Card_Token__c: record.AcctSeed__Customer__r.Latest_Credit_Card_Token__c,
      accLink: "/" + record.AcctSeed__Customer__c,
      bcLink: "/" + record.Id
    }));
  }

  // Method to fetch data from the server
  async fetchData(filter) {
    try {
      const result = await getApexData();
      this.data = this.mapData(result);
      this.data.forEach((res) => {
        res.accLink = "/" + res.AcctSeed__Customer__c;
        res.bcLink = "/" + res.Id;
      });
      this.data = filter ? this.data.filter((record) => record.Payment_Status__c === filter) : this.data;
    } catch (error) {
      this.handleTransactionError(error);
      this.toastEventFire("Error", "Failed to fetch data.", "error");
    }
  }

  // Method to get transaction data
  prepareTransactionData(row) {
    return {
      billingId: row.Id,
      mandate: row.Mandate_Id__c,
      charge_date: row.Charge_date__c,
      amount: row.AcctSeed__Balance__c,
      accountId: row.AcctSeed__Customer__c,
      stripeToken: row.AcctSeed__Stripe_Customer_Id__c,
      currentToken: row.AcctSeed__Customer_Latest_Credit_Card_Token__c,
      gateway: row.Payment_Gateway__c,
      payment_status__c: row.Payment_Status__c
    };
  }

  // Handler for row-level actions in the datatable
  async handleRowAction(event) {
    const { action, row } = event.detail;

    const transactionData = this.prepareTransactionData(row); 

    if (action.name === "runAPI") {
      try {
        const errorMessage = this.validateTransactionData(transactionData);
        if (errorMessage) {
          this.toastEventFire(errorMessage);
          return;
        }

        const gatewayInitiationMap = {
          GoCardLess: "initiateGoCardlessTransaction",
          Braintree: "initiateBraintreeTransaction",
          Stripe: "initiateStripeTransaction",
          "Braintree and Stripe": "initiateBraintreeTransaction"
        };

        const initiateTransaction = gatewayInitiationMap[transactionData.gateway];
        if (initiateTransaction) {
          await this[initiateTransaction]([transactionData]);
        } else {
          this.toastEventFire("Not enough data was found to process the transaction.");
        }
      } catch (error) {
        this.handleTransactionError(error);
      }
    }
  }

  // Method to validate transaction data before processing
  validateTransactionData(transactionData) {
    const gateway = transactionData.gateway;
    const paymentStatus = transactionData.payment_status__c;

    if (paymentStatus === "Uncharged" || paymentStatus === "Unsuccessful") {
      if (gateway === "GoCardLess" && !transactionData.mandate) {
        return "Mandate ID is required for GoCardLess gateway.";
      } else if (gateway === "Braintree" && !transactionData.currentToken) {
        return "Payment Token is required for Braintree gateway.";
      } else if (gateway === "Stripe" && !transactionData.stripeToken) {
        return "A valid customer ID is required for Stripe gateway.";
      } else if (gateway === "Braintree and Stripe" && !transactionData.currentToken) {
        return "Payment Token is required for Braintree gateway.";
      } else if (gateway === "Unknown") {
        return "The payment gateway for this billing is unknown.";
      }
    } else if (paymentStatus === "Pending") {
      return "The payment is in pending process.";
    } else if (paymentStatus === "Successful") {
      return "The payment is already charged.";
    }

    return null;
  }

  // Handler for confirming the processing of all payments
  async handleConfirmClick() {
    const message = "Do you want to process all payments?";
    const result = await LightningConfirm.open({
      message: message,
      variant: "default",
      label: "Confirm?"
    });

    if (result) {
      await this.chargeAllRenewals();
    }
  }

  /***  Methods to initiate transactions with different payment gateways  ***/ 
  async initiateBraintreeTransaction(dataToProcess) {
    this.showSpinner = true;
    try {
      const processedTransactions = [];
      for (let transactionData of dataToProcess) {
        try {
          const { accountId, amount, billingId, currentToken } = transactionData;
          const result = await processTransaction({ currentToken, amount, accountId, billingId });
          const parsedResult = JSON.parse(result);
          const resultId = this.handleTransactionResult(parsedResult, "BRAINTREE");
          if (resultId) {
            processedTransactions.push(resultId);
            // this.data = this.data.filter((e) => e.Id !== billingId);
          }
        } catch (error) {
          this.handleTransactionError(error);
        }
      }
      return processedTransactions.filter(Boolean);
    } catch (error) {
      this.handleTransactionError(error);
    } finally {
      this.showSpinner = false;
    }
  }

  async initiateGoCardlessTransaction(dataToProcess) {
    this.showSpinner = true;
    try {
      const processedTransactions = [];
      for (let transactionData of dataToProcess) {
        try {
          const { billingId, accountId, amount, mandate, charge_date } = transactionData;
          const amountInCents = amount * 100;
          const currency = "USD";
          const description = null;
          const retry_if_possible = true;

          const requestBody = JSON.stringify({
            payments: {
              amount: amountInCents,
              currency,
              description,
              // charge_date,
              retry_if_possible,
              links: {
                mandate
              }
            }
          });
          const result = await processGoCardlessTransaction({ requestBody, billingId, accountId });
          const response = JSON.parse(result);
          const resultId = this.handleTransactionResult(response, "GOCARDLESS");

          if (resultId) {
            processedTransactions.push(resultId);
            // this.data = this.data.filter((e) => e.Id !== billingId);
          }
        } catch (error) {
          this.handleTransactionError(error);
        }
      }
      return processedTransactions.filter(Boolean);
    } catch (error) {
      this.handleTransactionError(error);
    } finally {
      this.showSpinner = false;
    }
  }

  async initiateStripeTransaction(dataToProcess) {
    this.showSpinner = true;
    try {
      const processedTransactions = [];
      for (let transactionsData of dataToProcess) {
        try {
          const { billingId, accountId, amount, stripeToken } = transactionsData;
          const amountInCents = amount * 100;
          const currencyType = "usd";
          const result = await processStripeTransaction({
            amount: amountInCents,
            currencyType,
            customerId: stripeToken,
            billingId,
            accountId
          });
          const response = JSON.parse(result);
          const stripeId = this.handleTransactionResult(response, "STRIPE");

          if (stripeId) {
            processedTransactions.push(stripeId);
            // this.data = this.data.filter((e) => e.Id !== billingId);
          }
        } catch (error) {
          this.handleTransactionError(error);
        }
      }
      return processedTransactions.filter(Boolean);
    } catch (error) {
      this.handleTransactionError(error);
    } finally {
      this.showSpinner = false;
    }
  }

  // Method to process all eligible renewals
  async chargeAllRenewals() {
    this.showSpinner = true;

    const filteredBraintreeData = this.data.filter(
      (e) =>
        e.AcctSeed__Customer__c &&
        e.AcctSeed__Balance__c &&
        e.Id &&
        (e.Payment_Gateway__c ===  "Braintree and Stripe" || e.Payment_Gateway__c === "Braintree") &&
        e.AcctSeed__Customer_Latest_Credit_Card_Token__c &&
        (e.Payment_Status__c === "Uncharged" || e.Payment_Status__c === "Unsuccessful")
    );

    const filteredGcData = this.data.filter(
      (e) =>
        e.Mandate_Id__c &&
        e.AcctSeed__Customer__c &&
        e.AcctSeed__Balance__c &&
        e.Id &&
        e.Payment_Gateway__c ===  "GoCardLess" &&
        (e.Payment_Status__c === "Uncharged" || e.Payment_Status__c === "Unsuccessful")
    );

    const filteredStripeData = this.data.filter(
      (e) =>
        e.AcctSeed__Stripe_Customer_Id__c &&
        e.AcctSeed__Customer__c &&
        e.AcctSeed__Balance__c &&
        e.Id &&
        e.Payment_Gateway__c ===  "Stripe" &&
        (e.Payment_Status__c === "Uncharged" || e.Payment_Status__c === "Unsuccessful")
    );

    if (filteredBraintreeData.length === 0 && filteredGcData.length === 0 && filteredStripeData.length === 0) {
      this.toastEventFire("No eligible data found for transactions.", "", "warning");
      this.showSpinner = false;
      return;
    }

    const braintreeTransactions = filteredBraintreeData.map((transactionData) => ({
      accountId: transactionData.AcctSeed__Customer__c,
      amount: transactionData.AcctSeed__Balance__c,
      billingId: transactionData.Id,
      currentToken: transactionData.AcctSeed__Customer_Latest_Credit_Card_Token__c
    }));

    const goCardLessTransactions = filteredGcData.map((transactionData) => ({
      billingId: transactionData.Id,
      accountId: transactionData.AcctSeed__Customer__c,
      amount: transactionData.AcctSeed__Balance__c,
      mandate: transactionData.Mandate_Id__c,
      charge_date: transactionData.Charge_date__c
    }));

    const stripeTransactions = filteredStripeData.map((transactionData) => ({
      billingId: transactionData.Id,
      amount: transactionData.AcctSeed__Balance__c,
      accountId: transactionData.AcctSeed__Customer__c,
      stripeToken: transactionData.AcctSeed__Stripe_Customer_Id__c
    }));

    const processedBraintreeTransactions = filteredBraintreeData.length
      ? await this.initiateBraintreeTransaction(braintreeTransactions)
      : [];
    const processedGoCardLessTransactions = filteredGcData.length
      ? await this.initiateGoCardlessTransaction(goCardLessTransactions)
      : [];
    const processedStripeTransactions = filteredStripeData.length
      ? await this.initiateStripeTransaction(stripeTransactions)
      : [];

    const totalProcessedTransactions =
      processedBraintreeTransactions.length +
      processedGoCardLessTransactions.length +
      processedStripeTransactions.length;

    if (totalProcessedTransactions > 1) {
      this.toastEventFire(`Successfully processed ${totalProcessedTransactions} transactions`, ``, `success`);
    }
    this.showSpinner = false;
  }

  // Method to handle transaction results and update UI
  handleTransactionResult(parsedResult, paymentType) {
    if (!parsedResult) {
      throw new Error("Invalid input: parsedResult is required.");
    }

    this.fetchData();

    let toastHead = "";
    let toastMessage = "";
    let toastType = "";
    let transactionId = "";

    //Braintree Data
    if (paymentType === "BRAINTREE") {
      const { id, status } = parsedResult.data?.chargePaymentMethod?.transaction || {};

      if (status === "SUBMITTED_FOR_SETTLEMENT") {
        transactionId = id;
        toastHead = `Braintree transaction processed successfully`;
        toastMessage = `Status: ${status}`;
        toastType = "success";
      } else {
        toastHead = "Failed to process Braintree transaction";
        toastMessage = status;
        transactionId = "";
        toastType = "error";
      }

      if (parsedResult?.errors) {
        toastHead = `Failed to process Braintree transaction`;
        toastMessage = `${parsedResult?.errors[0]?.message}`;
        toastType = "error";
      }
    }

    //GoCardLess Data
    else if (paymentType === "GOCARDLESS") {
      const { payments, error } = parsedResult;
      if (payments) {
        const { id, status, amount, currency, charge_date } = payments;
        transactionId = id;
        toastHead = `GoCardLess transaction processed successfully`;
        toastMessage = `Status: ${status} and Charge date: ${charge_date}`;
        toastType = "success";
      } else if (error) {
        const { code: statusCode, errors } = error;
        errors.forEach((errorObj) => {
          const { reason, message, field } = errorObj;
          toastHead = `Error: ${message}.`;
          toastMessage = `Status Code: ${statusCode} Reason or Field: ${reason ? reason : field}`;
          toastType = "error";
        });
      }
    }

    //Stripe Data
    else if (paymentType === "STRIPE") {
      const { id, amount, currency, status } = parsedResult;
      if (id) {
        transactionId = id;
        toastHead = `Stripe transaction processed successfully`;
        toastMessage = `Status: ${status} with Id: ${id}`;
        toastType = status === "succeeded" ? "success" : "error";
      } else if (parsedResult.error) {
        const { message, param } = parsedResult.error;
        toastHead = `Field: ${param}`;
        toastMessage = message;
        toastType = "error";
      }
    }

    this.toastEventFire(toastHead, toastMessage, toastType);

    return transactionId;
  }

  // Method to handle errors during transaction processing
  handleTransactionError(error) {
    console.error("Error:", error);

    const statusText = error?.statusText || "Unknown Error";
    const statusCode = error?.status || "N/A";
    const errorMessage = `${statusText} ${statusCode}`;
    const errorDetails = error?.body?.message || "Something went wrong";

    this.toastEventFire(errorMessage, errorDetails, "error");
  }

  // Method to fire a toast event for displaying messages to the user
  toastEventFire(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}