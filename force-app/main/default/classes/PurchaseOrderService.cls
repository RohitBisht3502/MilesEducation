public without sharing class PurchaseOrderService {

    public class PurchaseOrderRequest {
        @AuraEnabled public Id leadId;
        @AuraEnabled public Decimal discount;
        @AuraEnabled public Decimal downPayment;
        @AuraEnabled public String addressType;
        @AuraEnabled public List<LineItemRequest> items;
    }

    public class LineItemRequest {
        @AuraEnabled public Id productId;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal qty;
        @AuraEnabled public String learningType;
    }

    public class AddressStatusDTO {
        @AuraEnabled public Boolean hasBilling;
        @AuraEnabled public Boolean hasShipping;
    }

    public class ProductDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String productCode;
        @AuraEnabled public String family;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public String type;

        public ProductDTO(Id id, String name, String code, String family, Decimal price,String type) {
            this.id = id;
            this.name = name;
            this.productCode = code;
            this.family = family;
            this.unitPrice = price;
            this.type = type;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ProductDTO> getActiveProducts(Id recordId) {
        List<ProductDTO> products = new List<ProductDTO>();
        String familyFilter = null;
        Boolean isConvertedStudent = false;

        Boolean isCairaRecordType = false;

        if (recordId != null && recordId.getSObjectType() == Lead__c.SObjectType) {
            Lead__c leadRec = [SELECT Course__c, RecordTypeId, Student__c FROM Lead__c WHERE Id = :recordId LIMIT 1];
            isConvertedStudent = (leadRec.Student__c != null);
            String recordTypeName;
            if (leadRec.RecordTypeId != null) {
                Schema.RecordTypeInfo rti =
                    Schema.SObjectType.Lead__c.getRecordTypeInfosById().get(leadRec.RecordTypeId);
                if (rti != null) {
                    recordTypeName = rti.getName();
                }
            }

            Set<String> allowedRecordTypes = new Set<String>{
                'CAIRA', 'CMA', 'CPA', 'MCOM', 'US Pathway'
            };

            if (!String.isBlank(recordTypeName) && allowedRecordTypes.contains(recordTypeName)) {
                familyFilter = recordTypeName;
            } else {
                familyFilter = leadRec.Course__c;
            }

            isCairaRecordType = (recordTypeName == 'CAIRA');
        }

        List<PricebookEntry> entries;
        if (String.isBlank(familyFilter)) {
            entries = [SELECT Product2Id, Product2.Name, Product2.ProductCode, Product2.Family, Product2.type__c, Product2.CAIRA_Level__c, UnitPrice FROM PricebookEntry WHERE IsActive = true];
        } else {
            entries = [SELECT Product2Id, Product2.Name, Product2.ProductCode, Product2.Family, Product2.type__c, Product2.CAIRA_Level__c, UnitPrice FROM PricebookEntry WHERE IsActive = true AND Product2.Family = :familyFilter];
        }

        for (PricebookEntry pbe : entries) {
            Decimal unitPrice = pbe.UnitPrice;

            if (isConvertedStudent && isCairaRecordType &&
                pbe.Product2 != null &&
                pbe.Product2.Family == 'CAIRA' &&
                pbe.Product2.CAIRA_Level__c == 'Level 1') {
                unitPrice = 0;
            }

            products.add(new ProductDTO(
                pbe.Product2Id,
                pbe.Product2.Name,
                pbe.Product2.ProductCode,
                pbe.Product2.Family,
                unitPrice,
                pbe.Product2.type__c
            ));
        }

        return products;
    }

    @AuraEnabled
    public static Id save(String requestJson) {
        try {
            PurchaseOrderRequest req = (PurchaseOrderRequest) JSON.deserialize(
                requestJson, 
                PurchaseOrderRequest.class
            );

            System.debug('Purchase Order Request: ' + requestJson);
            validateRequest(req);

            RecordContext context = identifyRecordContext(req.leadId);
            validateAddress(context, req);

            Lead__c lead = fetchLeadIfNeeded(context.leadRecordId);
            Lead candidate = fetchCandidateIfNeeded(lead);
            Account student = fetchStudentIfNeeded(context.studentAccountId);

            if (student == null && lead != null && lead.Student__c != null) {
                student = fetchStudentIfNeeded(lead.Student__c);
            }

            // api callout to miles
           // Callout_PurchaseOrderService.CalloutResult calloutRes = callExternalPurchaseService(req, lead, candidate);

            Purchase_Order__c po    = createPurchaseOrder(req, context, lead, candidate, student);
            po.Purchase_Order_Id__c = 'Testing 123';
            //  po.Purchase_Order_Id__c = String.valueOf(calloutRes.purchaseId);
            // po.Response_Payload__c  = calloutRes.responseBody;
            insert po;

            createLineItems(po.Id, req.items);
            updateCairaLevelIfNeeded(context, lead, req.items);
            createTransaction(po.Id, req.downPayment, req.leadId);

            return po.Id;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Save failed: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void saveAddress(
        Id recordId,
        String addressType,
        Map<String, String> address
    ) {
        if (recordId.getSObjectType() == Lead__c.SObjectType) {

            Lead__c leadRec = [SELECT Candidate__c, Student__c FROM Lead__c WHERE Id = :recordId];

            if (leadRec.Student__c != null) {
                Account acc = [SELECT Id FROM Account WHERE Id = :leadRec.Student__c];

                if (addressType == 'billing') {
                    acc.BillingStreet = address.get('street');
                    acc.BillingCity = address.get('city');
                    acc.BillingState = address.get('state');
                    acc.BillingPostalCode = address.get('postal');
                    acc.BillingCountry = address.get('country');
                } else {
                    acc.ShippingStreet = address.get('street');
                    acc.ShippingCity = address.get('city');
                    acc.ShippingState = address.get('state');
                    acc.ShippingPostalCode = address.get('postal');
                    acc.ShippingCountry = address.get('country');
                }

                update acc;
            } else {
                Lead candidate = [SELECT Id FROM Lead WHERE Id = :leadRec.Candidate__c];

                if (addressType == 'billing') {
                    candidate.Street = address.get('street');
                    candidate.City = address.get('city');
                    candidate.State = address.get('state');
                    candidate.PostalCode = address.get('postal');
                    candidate.Country = address.get('country');
                } else {
                    candidate.Shipping_Street__c = address.get('street');
                    candidate.Shipping_City__c = address.get('city');
                    candidate.Shipping_State__c = address.get('state');
                    candidate.Shipping_Postal_Code__c = address.get('postal');
                    candidate.Shipping_Country__c = address.get('country');
                }

                update candidate;
            }
        }

        if (recordId.getSObjectType() == Course_Enrolled__c.SObjectType) {

            Course_Enrolled__c ce = [SELECT Student__c FROM Course_Enrolled__c WHERE Id = :recordId];

            Account acc = [SELECT Id FROM Account WHERE Id = :ce.Student__c];

            if (addressType == 'billing') {
                acc.BillingStreet = address.get('street');
                acc.BillingCity = address.get('city');
                acc.BillingState = address.get('state');
                acc.BillingPostalCode = address.get('postal');
                acc.BillingCountry = address.get('country');
            } else {
                acc.ShippingStreet = address.get('street');
                acc.ShippingCity = address.get('city');
                acc.ShippingState = address.get('state');
                acc.ShippingPostalCode = address.get('postal');
                acc.ShippingCountry = address.get('country');
            }

            update acc;
        }
    }

    private static void createTransaction(
        Id purchaseOrderId,
        Decimal amountReceived,
        Id leadId
    ) {
        if (amountReceived == null || amountReceived <= 0) {
            return; // No payment → no transaction
        }

        Transcation__c txn = new Transcation__c();

        txn.Purchase_Orders__c = purchaseOrderId;

        txn.Payment__c = amountReceived;
        txn.Status__c  = 'Initiated';

        insert txn;
    }

    private static void validateRequest(PurchaseOrderRequest req) {
        if (req == null || req.items == null || req.items.isEmpty()) {
            throw new AuraHandledException('Items are required');
        }

        for (LineItemRequest li : req.items) {
            if (li == null || li.productId == null) {
                throw new AuraHandledException('Product Id is required');
            }
            if (li.qty == null || li.qty <= 0) {
                throw new AuraHandledException('Qty must be greater than zero');
            }
            if (li.unitPrice == null || li.unitPrice < 0) {
                throw new AuraHandledException('Unit Price is invalid');
            }
        }
    }

    private static RecordContext identifyRecordContext(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required');
        }

        RecordContext context = new RecordContext();
        Schema.SObjectType sobType = recordId.getSObjectType();

        if (sobType == Lead__c.SObjectType) {
            context.leadRecordId = recordId;
        } else if (sobType == Course_Enrolled__c.SObjectType) {
            context.courseEnrolledId = recordId;
            Course_Enrolled__c ce = [SELECT Id, Student__c FROM Course_Enrolled__c WHERE Id = :recordId LIMIT 1];
            context.studentAccountId = ce.Student__c;
        } else {
            throw new AuraHandledException('Unsupported record type for Purchase Order creation');
        }

        return context;
    }

    private static void validateAddress(RecordContext context, PurchaseOrderRequest req) {

        Boolean shippingRequired = hasStudyMaterial(req.items);

        if (context.courseEnrolledId != null) {

            if (context.studentAccountId == null) {
                throw new AuraHandledException('Student (Account) is not linked.');
            }

            Account acc = [SELECT BillingStreet, BillingCity, ShippingStreet, ShippingCity FROM Account WHERE Id = :context.studentAccountId LIMIT 1];

            // Billing is ALWAYS mandatory
            if (!hasCompleteAddress(acc.BillingStreet, acc.BillingCity, null, null, null)) {
                throw new AuraHandledException(
                    'Billing address is mandatory before creating Purchase Order.'
                );
            }

            // Shipping mandatory only for Study Material
            if (shippingRequired &&
                !hasCompleteAddress(acc.ShippingStreet, acc.ShippingCity, null, null, null)) {
                throw new AuraHandledException(
                    'Shipping address is mandatory for Study Material.'
                );
            }

        } else {

            Lead__c leadRec = [SELECT Candidate__c, Student__c FROM Lead__c WHERE Id = :context.leadRecordId LIMIT 1];

            if (leadRec.Student__c != null) {
                Account acc = [SELECT BillingStreet, BillingCity, ShippingStreet, ShippingCity FROM Account WHERE Id = :leadRec.Student__c LIMIT 1];

                if (!hasCompleteAddress(acc.BillingStreet, acc.BillingCity, null, null, null)) {
                    throw new AuraHandledException(
                        'Billing address is mandatory before creating Purchase Order.'
                    );
                }

                if (shippingRequired &&
                    !hasCompleteAddress(acc.ShippingStreet, acc.ShippingCity, null, null, null)) {
                    throw new AuraHandledException(
                        'Shipping address is mandatory for Study Material.'
                    );
                }
            } else {
                Lead candidate = [SELECT Street, City, Shipping_Street__c, Shipping_City__c FROM Lead WHERE Id = :leadRec.Candidate__c LIMIT 1];

                if (!hasCompleteAddress(candidate.Street, candidate.City, null, null, null)) {
                    throw new AuraHandledException(
                        'Billing address is mandatory before creating Purchase Order.'
                    );
                }

                if (shippingRequired &&
                    !hasCompleteAddress(candidate.Shipping_Street__c, candidate.Shipping_City__c, null, null, null)) {
                    throw new AuraHandledException(
                        'Shipping address is mandatory for Study Material.'
                    );
                }
            }
        }
    }

    private static Boolean hasStudyMaterial(List<LineItemRequest> items) {
        if (items == null) return false;

        for (LineItemRequest li : items) {
            if (li != null && li.learningType == 'Study Material') {
                return true;
            }
        }
        return false;
    }

    private static Lead__c fetchLeadIfNeeded(Id leadRecordId) {
        if (leadRecordId == null) return null;

        Lead__c lead = [SELECT Id, Candidate__c, Course__c, Student__c, RecordTypeId FROM Lead__c WHERE Id = :leadRecordId LIMIT 1];

        if (lead.Candidate__c == null) {
            throw new AuraHandledException('Candidate is not linked to this Lead');
        }

        return lead;
    }

    private static Lead fetchCandidateIfNeeded(Lead__c lead) {
        if (lead == null) return null;

        List<Lead> candidates = [SELECT Street, City, State, PostalCode, Country, Shipping_Street__c, Shipping_City__c, Shipping_State__c, Shipping_Postal_Code__c, Shipping_Country__c,UUID__c FROM Lead WHERE Id = :lead.Candidate__c];

        if (candidates.isEmpty()) {
            throw new AuraHandledException('Candidate Lead not found');
        }

        return candidates[0];
    }

    private static Account fetchStudentIfNeeded(Id studentAccountId) {
        if (studentAccountId == null) return null;

        return [SELECT BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry, ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry FROM Account WHERE Id = :studentAccountId LIMIT 1];
    }

    private static Purchase_Order__c createPurchaseOrder(
        PurchaseOrderRequest req,
        RecordContext context,
        Lead__c lead,
        Lead candidate,
        Account student
    ) {
        Purchase_Order__c po = new Purchase_Order__c();

        if (context.courseEnrolledId != null) {
            po.Course_Enrolled__c = context.courseEnrolledId;
            if (context.leadRecordId != null) {
                po.Lead__c = context.leadRecordId;
            }
        } else {
            po.Lead__c = context.leadRecordId;
        }

        if (lead != null) {
            po.Candidate__c = lead.Candidate__c;
        }

        po.Discount_Amount__c = req.discount;
        // po.Down_Payment__c = req.downPayment;
        po.Purchase_Order_Date__c = Date.today();

        setAddress(po, req.addressType, context, candidate, student);

        return po;
    }

    private static void setAddress(
        Purchase_Order__c po,
        String addressType,
        RecordContext context,
        Lead candidate,
        Account student
    ) {
        if (student != null && (context.courseEnrolledId != null || context.leadRecordId != null)) {
            if (addressType == 'billing') {
                po.Shipping_Street__c = student.BillingStreet;
                po.Shipping_City__c = student.BillingCity;
                po.Shipping_State__c = student.BillingState;
                po.Shipping_Postal_Code__c = student.BillingPostalCode;
                po.Shipping_Country__c = student.BillingCountry;
            } else {
                po.Shipping_Street__c = student.ShippingStreet;
                po.Shipping_City__c = student.ShippingCity;
                po.Shipping_State__c = student.ShippingState;
                po.Shipping_Postal_Code__c = student.ShippingPostalCode;
                po.Shipping_Country__c = student.ShippingCountry;
            }
        } else if (candidate != null) {
            if (addressType == 'billing') {
                po.Shipping_Street__c = candidate.Street;
                po.Shipping_City__c = candidate.City;
                po.Shipping_State__c = candidate.State;
                po.Shipping_Postal_Code__c = candidate.PostalCode;
                po.Shipping_Country__c = candidate.Country;
            } else {
                po.Shipping_Street__c = candidate.Shipping_Street__c;
                po.Shipping_City__c = candidate.Shipping_City__c;
                po.Shipping_State__c = candidate.Shipping_State__c;
                po.Shipping_Postal_Code__c = candidate.Shipping_Postal_Code__c;
                po.Shipping_Country__c = candidate.Shipping_Country__c;
            }
        }
    }

    private static void createLineItems(Id purchaseOrderId, List<LineItemRequest> items) {
        List<Purchase_Order_Line_Item__c> lines = new List<Purchase_Order_Line_Item__c>();

        for (LineItemRequest li : items) {
            Purchase_Order_Line_Item__c row = new Purchase_Order_Line_Item__c();
            row.Purchase_Order__c = purchaseOrderId;
            row.Product__c = li.productId;
            row.Quantity__c = li.qty;
            row.Unit_Price__c = li.unitPrice;
            lines.add(row);
        }

        insert lines;
    }

    @AuraEnabled
    public static Boolean checkLeadAddress(Id leadRecordId) {
        Lead__c leadRec = [SELECT Candidate__c FROM Lead__c WHERE Id = :leadRecordId LIMIT 1];

        if (leadRec.Candidate__c == null) {
            throw new AuraHandledException('Candidate is not linked to this Lead');
        }

        Lead candidate = [SELECT Street, City, State, PostalCode, Country, Shipping_Street__c, Shipping_City__c, Shipping_State__c, Shipping_Postal_Code__c, Shipping_Country__c FROM Lead WHERE Id = :leadRec.Candidate__c LIMIT 1];

        return hasCompleteAddress(
            candidate.Street, candidate.City, candidate.State, 
            candidate.PostalCode, candidate.Country
        ) || hasCompleteAddress(
            candidate.Shipping_Street__c, candidate.Shipping_City__c, 
            candidate.Shipping_State__c, candidate.Shipping_Postal_Code__c, 
            candidate.Shipping_Country__c
        );
    }

    public static Boolean checkStudentAccountAddress(Id accountId) {
        Account acc = [SELECT BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry, ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry FROM Account WHERE Id = :accountId LIMIT 1];

        return hasCompleteAddress(
            acc.BillingStreet, acc.BillingCity, acc.BillingState, 
            acc.BillingPostalCode, acc.BillingCountry
        ) || hasCompleteAddress(
            acc.ShippingStreet, acc.ShippingCity, acc.ShippingState, 
            acc.ShippingPostalCode, acc.ShippingCountry
        );
    }

    @AuraEnabled
    public static AddressStatusDTO checkAddressByRecordId(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required');
        }

        AddressStatusDTO res = new AddressStatusDTO();
        Schema.SObjectType sobType = recordId.getSObjectType();

        if (sobType == Lead__c.SObjectType) {
            Lead__c leadRec = [SELECT Candidate__c, Student__c FROM Lead__c WHERE Id = :recordId LIMIT 1];

            if (leadRec.Student__c != null) {
                Account acc = [SELECT BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry, ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry FROM Account WHERE Id = :leadRec.Student__c];

                res.hasBilling = hasCompleteAddress(
                    acc.BillingStreet, acc.BillingCity, acc.BillingState,
                    acc.BillingPostalCode, acc.BillingCountry
                );

                res.hasShipping = hasCompleteAddress(
                    acc.ShippingStreet, acc.ShippingCity, acc.ShippingState,
                    acc.ShippingPostalCode, acc.ShippingCountry
                );
            } else {
                Lead candidate = [SELECT Street, City, State, PostalCode, Country, Shipping_Street__c, Shipping_City__c, Shipping_State__c, Shipping_Postal_Code__c, Shipping_Country__c FROM Lead WHERE Id = :leadRec.Candidate__c];

                res.hasBilling = hasCompleteAddress(
                    candidate.Street, candidate.City, candidate.State,
                    candidate.PostalCode, candidate.Country
                );

                res.hasShipping = hasCompleteAddress(
                    candidate.Shipping_Street__c, candidate.Shipping_City__c,
                    candidate.Shipping_State__c, candidate.Shipping_Postal_Code__c,
                    candidate.Shipping_Country__c
                );
            }

            return res;
        }

        if (sobType == Course_Enrolled__c.SObjectType) {
            Course_Enrolled__c ce = [SELECT Student__c FROM Course_Enrolled__c WHERE Id = :recordId LIMIT 1];

            Account acc = [SELECT BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry, ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry FROM Account WHERE Id = :ce.Student__c];

            res.hasBilling = hasCompleteAddress(
                acc.BillingStreet, acc.BillingCity, acc.BillingState,
                acc.BillingPostalCode, acc.BillingCountry
            );

            res.hasShipping = hasCompleteAddress(
                acc.ShippingStreet, acc.ShippingCity, acc.ShippingState,
                acc.ShippingPostalCode, acc.ShippingCountry
            );

            return res;
        }

        throw new AuraHandledException('Unsupported record type');
    }

    private static Boolean hasCompleteAddress(
        String street, String city, String state, String postalCode, String country
    ) {
        return !String.isBlank(street) && !String.isBlank(city);
    }

    private static Callout_PurchaseOrderService.CalloutResult callExternalPurchaseService( PurchaseOrderRequest req, Lead__c lead, Lead candidate ) {

        Set<Id> prodIds = new Set<Id>();
        for (LineItemRequest li : req.items) {
            if (li != null && li.productId != null)
                prodIds.add(li.productId);
        }

        Map<Id, Product2> prodMap = new Map<Id, Product2>();
        if (!prodIds.isEmpty()) {
            prodMap = new Map<Id, Product2>([SELECT Id, Name, ProductCode FROM Product2 WHERE Id IN :prodIds]);
        }

        Callout_PurchaseOrderService.Request extReq = new Callout_PurchaseOrderService.Request();
        extReq.source       = 'sf';
        extReq.sf_id        = String.valueOf(lead.Id);
        extReq.sf_lead_id   = String.valueOf(req.leadId);
        extReq.uuid         = candidate.UUID__c;
        extReq.down_payment = req.discount;
        //extReq.created_by   = UserInfo.getName();
        extReq.created_by   = 'MPE226';

        Callout_PurchaseOrderService.RequestItem item = new Callout_PurchaseOrderService.RequestItem();
        //  item.program = String.valueOf(lead.Course__c);
        item.program = 'CPA';
        Boolean hasTraining = false;
        Boolean hasStudyMaterial = false;

        item.skus = new List<String>();
        item.enrolment_line_items = new List<Callout_PurchaseOrderService.EnrolmentLineItem>();

        Decimal total = 0;

        for (LineItemRequest li : req.items) {
            if (li == null) continue;

            if (!String.isBlank(li.learningType)) {
                if (li.learningType == 'Training') hasTraining = true;
                if (li.learningType == 'Study Material') hasStudyMaterial = true;
            }

            Product2 p = prodMap.get(li.productId);

            String skuVal =
                (p != null && !String.isBlank(p.ProductCode)) ? p.ProductCode :
                (p != null ? p.Name : null);

            if (!String.isBlank(skuVal))
                item.skus.add(skuVal);

            Callout_PurchaseOrderService.EnrolmentLineItem eli =
                new Callout_PurchaseOrderService.EnrolmentLineItem();

            eli.item_name = (p != null ? p.Name : 'Item');

            Decimal lineAmount =
                (li.unitPrice != null ? li.unitPrice : 0) *
                (li.qty != null ? li.qty : 0);

            eli.price          = lineAmount;
            eli.price_with_gst = lineAmount;
            eli.discound       = 0;
            eli.final_price    = lineAmount;

            item.enrolment_line_items.add(eli);

            total += lineAmount;
        }

        item.has_training       = hasTraining;
        item.has_study_material = hasStudyMaterial;

        item.actual_price = total;
        item.agreed_fee   = total;
        item.discount     = req.discount;
        item.loan_id      = null;

        extReq.purchase_items =
            new List<Callout_PurchaseOrderService.RequestItem>{ item };

        Callout_PurchaseOrderService.CalloutResult result = Callout_PurchaseOrderService.createPurchase(extReq);

        if (result == null || result.purchaseId == null) {
            throw new AuraHandledException('External service did not return purchase_id. Purchase Order not created.');
        }

        return result;
    }

    private class RecordContext {
        public Id leadRecordId;
        public Id courseEnrolledId;
        public Id studentAccountId;
    }

    private static void updateCairaLevelIfNeeded(
        RecordContext context,
        Lead__c lead,
        List<LineItemRequest> items
    ) {
        if (context == null || context.leadRecordId == null || lead == null) return;
        if (items == null || items.isEmpty()) return;

        String recordTypeName;
        if (lead.RecordTypeId != null) {
            Schema.RecordTypeInfo rti =
                Schema.SObjectType.Lead__c.getRecordTypeInfosById().get(lead.RecordTypeId);
            if (rti != null) {
                recordTypeName = rti.getName();
            }
        }
        if (recordTypeName != 'CAIRA') return;

        Set<Id> prodIds = new Set<Id>();
        for (LineItemRequest li : items) {
            if (li != null && li.productId != null) {
                prodIds.add(li.productId);
            }
        }
        if (prodIds.isEmpty()) return;

        Map<Id, Product2> prodMap = new Map<Id, Product2>([SELECT Id, Family, CAIRA_Level__c, Is_Bundle__c FROM Product2 WHERE Id IN :prodIds]);

        Boolean hasLevel1 = false;
        Boolean hasLevel2 = false;
        Boolean hasLevel3 = false;
        for (LineItemRequest li : items) {
            Product2 p = prodMap.get(li.productId);
            if (p == null) continue;

            if (p.Is_Bundle__c) {
                hasLevel1 = true;
                hasLevel2 = true;
                hasLevel3 = true;
                continue;
            }

            if (p.CAIRA_Level__c == 'Level 1') hasLevel1 = true;
            if (p.CAIRA_Level__c == 'Level 2') hasLevel2 = true;
            if (p.CAIRA_Level__c == 'Level 3') hasLevel3 = true;
        }

        List<String> levels = new List<String>();
        if (hasLevel1) levels.add('Level 1');
        if (hasLevel2) levels.add('Level 2');
        if (hasLevel3) levels.add('Level 3');
        if (levels.isEmpty()) return;

        Lead__c upd = new Lead__c(
            Id = context.leadRecordId,
            Caira_Level__c = String.join(levels, ';')
        );
        update upd;
    }
}
