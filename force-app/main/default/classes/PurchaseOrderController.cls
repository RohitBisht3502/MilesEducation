public with sharing class PurchaseOrderController {

    /* =====================================================
       PRODUCT DTO (NO __c IN VARIABLE NAMES)
       ===================================================== */
    public class ProductDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String productCode;
        @AuraEnabled public String family;
        @AuraEnabled public Decimal unitPrice; // ✅ FIX

        public ProductDTO(
            Id id,
            String name,
            String code,
            String family,
            Decimal price
        ) {
            this.id = id;
            this.name = name;
            this.productCode = code;
            this.family = family;
            this.unitPrice = price;
        }
    }

    /* =====================================================
       PURCHASE DTOs
       ===================================================== */
    public class PurchaseItemDTO {
        @AuraEnabled public Id productId;
        @AuraEnabled public Integer quantity;
    }

    public class PurchaseRequestDTO {
        @AuraEnabled public Id studentId;
        @AuraEnabled public Id candidateId;
        @AuraEnabled public Id leadId;
        @AuraEnabled public Decimal discountAmount;
        @AuraEnabled public List<PurchaseItemDTO> items;
    }

    /* =====================================================
       FETCH ACTIVE PRODUCTS
       ===================================================== */
    @AuraEnabled(cacheable=true)
    public static List<ProductDTO> getActiveProducts() {

        Id stdPbId = [
            SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1
        ].Id;

        List<ProductDTO> products = new List<ProductDTO>();

        for (PricebookEntry pbe : [
            SELECT Product2Id,
                   Product2.Name,
                   Product2.ProductCode,
                   Product2.Family,
                   UnitPrice
            FROM PricebookEntry
            WHERE IsActive = true
          
        
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

    /* =====================================================
       CREATE PURCHASE ORDER + LINE ITEMS
       ===================================================== */
    @AuraEnabled
    public static Id createPurchaseOrder(PurchaseRequestDTO req) {

        if (req == null || req.items == null || req.items.isEmpty()) {
            throw new AuraHandledException('No products selected.');
        }

        Purchase_Order__c po = new Purchase_Order__c(
            Purchase_Order_Date__c = Date.today(),
            Status__c = 'Confirmed',
            Discount_Amount__c = req.discountAmount,
            Student__c = req.studentId,
            Candidate__c = req.candidateId,
            Lead__c = req.leadId
        );
        insert po;

        Set<Id> productIds = new Set<Id>();
        for (PurchaseItemDTO item : req.items) {
            if (item.productId != null) {
                productIds.add(item.productId);
            }
        }

        Id stdPbId = [
            SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1
        ].Id;

        Map<Id, Decimal> priceMap = new Map<Id, Decimal>();
        for (PricebookEntry pbe : [
            SELECT Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id IN :productIds
              AND Pricebook2Id = :stdPbId
              AND IsActive = true
        ]) {
            priceMap.put(pbe.Product2Id, pbe.UnitPrice);
        }

        List<Purchase_Order_Line_Item__c> lines =
            new List<Purchase_Order_Line_Item__c>();

        for (PurchaseItemDTO item : req.items) {
            if (item.quantity == null || item.quantity <= 0) continue;

            lines.add(new Purchase_Order_Line_Item__c(
                Purchase_Order__c = po.Id,
                Product__c = item.productId,
                Quantity__c = item.quantity,
                Unit_Price__c = priceMap.get(item.productId), // ✅ OBJECT FIELD
                Name = 'PO Item'
            ));
        }

        insert lines;
        return po.Id;
    }
}