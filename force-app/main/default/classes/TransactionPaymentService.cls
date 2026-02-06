public without sharing class TransactionPaymentService {

    public class PaymentContextDTO {
        @AuraEnabled public Decimal netPayableAmount;
        @AuraEnabled public Decimal remainingAmount;
        @AuraEnabled public List<TransactionDTO> transactions;
    }

    public class TransactionDTO {
        @AuraEnabled public Decimal payment;
        @AuraEnabled public String status;
    }

    @AuraEnabled(cacheable=true)
    public static PaymentContextDTO getPaymentContext(Id purchaseOrderId) {
        if (purchaseOrderId == null) {
            throw new AuraHandledException('Invalid Purchase Order');
        }

        String remainingFieldApi = resolveRemainingAmountFieldApi();
        String soql = 'SELECT Id, Net_Payable_Amount__c';
        if (String.isNotBlank(remainingFieldApi)) {
            soql += ', ' + remainingFieldApi;
        }
        soql += ' FROM Purchase_Order__c WHERE Id = :purchaseOrderId LIMIT 1';
        Purchase_Order__c po = (Purchase_Order__c) Database.query(soql);

        List<Transcation__c> txns = [
            SELECT Payment__c, Payment_Received__c, Status__c, CreatedDate
            FROM Transcation__c
            WHERE Purchase_Orders__c = :purchaseOrderId
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];

        Decimal receivedTotal = 0;
        if (!txns.isEmpty() && txns[0].Payment_Received__c != null) {
            receivedTotal = txns[0].Payment_Received__c;
        }

        Decimal netPayable = po.Net_Payable_Amount__c == null ? 0 : po.Net_Payable_Amount__c;
        Decimal remaining = null;

        if (String.isNotBlank(remainingFieldApi)) {
            Object remainingRaw = po.get(remainingFieldApi);
            if (remainingRaw instanceof Decimal) {
                remaining = (Decimal) remainingRaw;
            } else if (remainingRaw != null) {
                remaining = Decimal.valueOf(String.valueOf(remainingRaw));
            }
        }

        if (remaining == null) {
            remaining = netPayable - receivedTotal;
            if (remaining < 0) {
                remaining = 0;
            }
        }

        PaymentContextDTO out = new PaymentContextDTO();
        out.netPayableAmount = netPayable;
        out.remainingAmount = remaining;
        out.transactions = new List<TransactionDTO>();

        for (Transcation__c t : txns) {
            TransactionDTO row = new TransactionDTO();
            row.payment = t.Payment__c;
            row.status = t.Status__c;
            out.transactions.add(row);
        }

        return out;
    }

    private static String resolveRemainingAmountFieldApi() {
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Purchase_Order__c.fields.getMap();

        List<String> priorityCandidates = new List<String>{
            'Remaining_Amount__c',
            'Remaing_Amount__c',
            'Remaining_Payable_Amount__c',
            'Remaining_Payable__c'
        };

        for (String apiName : priorityCandidates) {
            if (fieldMap.containsKey(apiName)) {
                return apiName;
            }
        }

        List<String> keys = new List<String>(fieldMap.keySet());
        keys.sort();
        for (String key : keys) {
            if (!key.toLowerCase().contains('remain')) {
                continue;
            }
            Schema.DescribeFieldResult dfr = fieldMap.get(key).getDescribe();
            if (dfr.getType() == Schema.DisplayType.Currency ||
                dfr.getType() == Schema.DisplayType.Double ||
                dfr.getType() == Schema.DisplayType.Integer) {
                return key;
            }
        }
        return null;
    }

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
