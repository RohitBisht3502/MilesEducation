/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : PurchaseOrderService
 * Author          : Rohit Singh Bisht
 * Created Date    : Jan 8, 2026
 */

public class PurchaseOrderService {

    public class PurchaseOrderRequest{
        @AuraEnabled public Id leadId;
        @AuraEnabled public Decimal discount;
        @AuraEnabled public List<LineItemRequest> items;
    }

    public class LineItemRequest{
        @AuraEnabled public Id productId;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal qty;
		@AuraEnabled public String learningType;
    }


    public class ProductDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String productCode;
        @AuraEnabled public String family;
        @AuraEnabled public Decimal unitPrice; 

        public ProductDTO(Id id,String name, String code, String family, Decimal price) {
            this.id          = id;
            this.name        = name;
            this.productCode = code;
            this.family      = family;
            this.unitPrice   = price;
        }
    }


    /* =====================================================
       FETCH ACTIVE PRODUCTS
       ===================================================== */
    @AuraEnabled(cacheable=true)
    public static List<ProductDTO> getActiveProducts() {

        Id stdPbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;

        List<ProductDTO> products = new List<ProductDTO>();

        for (PricebookEntry pbe : [
            SELECT Product2Id, Product2.Name, Product2.ProductCode, Product2.Family, UnitPrice  FROM PricebookEntry WHERE IsActive = true        
        ]) {
            products.add(new ProductDTO(
                pbe.Product2Id,
                pbe.Product2.Name,
                pbe.Product2.ProductCode,
                pbe.Product2.Family,
                pbe.UnitPrice
            ));
        }

        return products;
    }

    @AuraEnabled
    public static Id save(String requestJson){
        try{
            if(String.isBlank(requestJson)){
                throw new AuraHandledException('Empty request');
            }

            PurchaseOrderRequest req =
                (PurchaseOrderRequest) JSON.deserialize(requestJson, PurchaseOrderRequest.class);

            if(req.leadId == null) throw new AuraHandledException('Lead Id is required');
            if(req.items == null || req.items.isEmpty()) throw new AuraHandledException('Items are required');

            for(LineItemRequest li : req.items){
                if(li == null) throw new AuraHandledException('Invalid line item');
                if(li.productId == null) throw new AuraHandledException('Product Id is required');
                if(li.qty == null || li.qty <= 0) throw new AuraHandledException('Qty must be greater than zero');
                if(li.unitPrice == null || li.unitPrice < 0) throw new AuraHandledException('Unit Price is invalid');
            }                

            Lead__c lead = [SELECT Id, Candidate__c,Course__c FROM Lead__c WHERE Id = :req.leadId LIMIT 1];

            Boolean hasTraining = false;
            Boolean hasStudyMaterial = false;

            for(LineItemRequest li : req.items){
                if (li != null && !String.isBlank(li.learningType)) {
                    if (li.learningType == 'Training') {
                        hasTraining = true;
                    }
                    if (li.learningType == 'Study Material') {
                        hasStudyMaterial = true;
                    }
                }
            }

            /* ------------------ CALL EXTERNAL API FIRST ------------------ */

        //     Callout_PurchaseOrderService.Request extReq = new Callout_PurchaseOrderService.Request();

        //     extReq.source = 'sf';
        //     extReq.sf_id = String.valueOf(req.leadId);
        //    // extReq.uuid = String.valueOf(Crypto.getRandomUUID());
        //     extReq.down_payment = 0;

        //     Callout_PurchaseOrderService.RequestItem item = new Callout_PurchaseOrderService.RequestItem();

        //     item.program = lead.Course__c;
        //     item.skus = new List<String>();
        //     item.actual_price = 0;
        //     item.agreed_price = 0;
        //     item.discount = req.discount;
        //     item.loan_id = null;

        //     item.has_training = hasTraining;
        //     item.has_study_material = hasStudyMaterial;

        //     extReq.purchase_items = new List<Callout_PurchaseOrderService.RequestItem>{ item };

        //     String externalPurchaseId = Callout_PurchaseOrderService.createPurchase(extReq);

            /* ------------------ INSERT PO ONLY AFTER SUCCESS ------------------ */

            Purchase_Order__c po = new Purchase_Order__c();
            po.Lead__c = req.leadId;
            po.Candidate__c = lead.Candidate__c;
            po.Discount_Amount__c = req.discount;
            po.Purchase_Order_Date__c = Date.today();
           // po.Purchase_Order_Id__c = externalPurchaseId;
            insert po;

            List<Purchase_Order_Line_Item__c> lines = new List<Purchase_Order_Line_Item__c>();

            for(LineItemRequest li : req.items){
                Purchase_Order_Line_Item__c row = new Purchase_Order_Line_Item__c();
                row.Purchase_Order__c = po.Id;
                row.Product__c = li.productId;
                row.Quantity__c = li.qty;
                row.Unit_Price__c = li.unitPrice;
                lines.add(row);
            }

            insert lines;

            return po.Id;

        } catch (AuraHandledException e){
            throw e;
        } catch (Exception e){
            throw new AuraHandledException('Save failed: ' + e.getMessage());
        }
    }
}