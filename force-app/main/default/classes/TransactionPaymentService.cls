public without sharing class TransactionPaymentService {

    @AuraEnabled
    public static void saveDownPayment(Id purchaseOrderId, Decimal amount) {

        if (purchaseOrderId == null || amount == null || amount <= 0) {
            throw new AuraHandledException('Invalid input');
        }

        // Get Purchase Order Net Payable Amount
        Purchase_Order__c po = [
            SELECT Id, Net_Payable_Amount__c
            FROM Purchase_Order__c
            WHERE Id = :purchaseOrderId
            LIMIT 1
        ];

        if (po.Net_Payable_Amount__c == null || po.Net_Payable_Amount__c <= 0) {
            throw new AuraHandledException('Net payable amount is not defined.');
        }

        //  Get last transaction to calculate running total
        List<Transcation__c> lastTxn = [
            SELECT Payment_Received__c
            FROM Transcation__c
            WHERE Purchase_Orders__c = :purchaseOrderId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Decimal previousTotal = 0;
        if (!lastTxn.isEmpty() && lastTxn[0].Payment_Received__c != null) {
            previousTotal = lastTxn[0].Payment_Received__c;
        }

        Decimal newTotal = previousTotal + amount;

        // VALIDATION: total payment should not exceed net payable
        if (newTotal > po.Net_Payable_Amount__c) {
            throw new AuraHandledException(
                'Down payment exceeds the net payable amount. Remaining payable is ₹'
                + (po.Net_Payable_Amount__c - previousTotal)
            );
        }

        //  Always create NEW transaction
        Transcation__c newTxn = new Transcation__c();
        newTxn.Purchase_Orders__c  = purchaseOrderId;
        newTxn.Payment__c          = amount;          
        // newTxn.Payment_Received__c = newTotal;        
        newTxn.Status__c           = 'Initiated';

        insert newTxn;

        Callout_PaymentUpdateApi.sendPaymentUpdate
            (
            purchaseOrderId,
            amount
        );
        
    }
}