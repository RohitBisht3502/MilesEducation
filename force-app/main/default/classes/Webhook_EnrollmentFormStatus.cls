@RestResource(urlMapping='/Webhook_EnrollmentFormStatus/*')
global without sharing class Webhook_EnrollmentFormStatus {

    @HttpPost
    global static String updateStatus() {
        try {
            // Read raw JSON request body
            String requestBody = RestContext.request.requestBody.toString();
            
            // Parse JSON input
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(requestBody);
            
            if (!payload.containsKey('purchaseOrderId') || !payload.containsKey('status')) {
                return 'Error: Missing required fields.';
            }
            
            String externalPOId = String.valueOf(payload.get('purchaseOrderId'));
            String status = String.valueOf(payload.get('status'));
            
            // Query by external purchase order ID
            List<Purchase_Order__c> poList = [SELECT Id, Status__c FROM Purchase_Order__c WHERE Purchase_Order_Id__c = :externalPOId LIMIT 1];
            
            if (poList.isEmpty()) {
                return 'Error: Purchase Order not found for Purchase_Order_Id__c = ' + externalPOId;
            }
            
            // Update status
            Purchase_Order__c po = poList[0];
            po.Status__c = status;
            update po;
            
            return 'Success: Purchase Order status updated.';
            
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
}