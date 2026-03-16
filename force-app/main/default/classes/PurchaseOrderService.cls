public without sharing class PurchaseOrderService {
    private static final String ADDRESS_TYPE_BILLING = 'billing';
    private static final String ADDRESS_TYPE_SHIPPING = 'shipping';
    private static final String RECORDTYPE_CAIRA = 'CAIRA';
    private static final String LEARNING_TYPE_TRAINING = 'Training';
    private static final String LEARNING_TYPE_STUDY = 'Study Material';
    private static final String STATUS_PENDING = 'Pending';
    private static final String STATUS_INITIATED = 'Initiated';
    private static final String SOURCE_SF = 'sf';
    private static final String CREATED_BY_DEFAULT = 'MPE226';
    private static final String CAIRA_LEVEL_1 = 'Level 1';
    private static final String CAIRA_LEVEL_2 = 'Level 2';
    private static final String CAIRA_LEVEL_3 = 'Level 3';

    private static final Set<String> ALLOWED_RECORD_TYPES = new Set<String>{
        RECORDTYPE_CAIRA, 'CMA', 'CPA', 'MCOM', 'US Pathway'
    };

    public class PurchaseOrderRequest {
        @AuraEnabled public Id leadId;
        @AuraEnabled public Decimal discount;
        @AuraEnabled public Decimal downPayment;
        @AuraEnabled public Decimal processingFee;
        @AuraEnabled public String phoneNumber;
        @AuraEnabled public String addressType;
        @AuraEnabled public String approvalComments;
        @AuraEnabled public List<LineItemRequest> items;
        @AuraEnabled public String loanId;
    }

    public class LineItemRequest {
        @AuraEnabled public Id productId;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal qty;
        @AuraEnabled public String learningType;
    }

    public class SimpleLineItem {
        public Id productId;
        public Decimal unitPrice;
        public Decimal qty;
        public SimpleLineItem(Id productId, Decimal unitPrice, Decimal qty) {
            this.productId = productId;
            this.unitPrice = unitPrice;
            this.qty = qty;
        }
    }

    public class ExpandedProduct {
        public Id productId;
        public String name;
        public String sku;
        public Decimal unitPrice;
        public Decimal qty;
        public ExpandedProduct(Id productId, String name, String sku, Decimal unitPrice, Decimal qty) {
            this.productId = productId;
            this.name = name;
            this.sku = sku;
            this.unitPrice = unitPrice;
            this.qty = qty;
        }
    }

    public class AddressStatusDTO {
        @AuraEnabled public Boolean hasBilling;
        @AuraEnabled public Boolean hasShipping;

        public AddressStatusDTO() {
            this.hasBilling = false;
            this.hasShipping = false;
        }
    }

    public class AddressDetailsDTO {
        @AuraEnabled public Map<String, String> billing;
        @AuraEnabled public Map<String, String> shipping;
        @AuraEnabled public String phone;

        public AddressDetailsDTO() {
            this.billing = new Map<String, String>();
            this.shipping = new Map<String, String>();
            this.phone = null;
        }
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
        List<PricebookEntry> entries;


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

            if (!String.isBlank(recordTypeName) && ALLOWED_RECORD_TYPES.contains(recordTypeName)) {
                familyFilter = recordTypeName;
            } else {
                familyFilter = leadRec.Course__c;
            }

            isCairaRecordType = (recordTypeName == RECORDTYPE_CAIRA);
        }

        if (String.isBlank(familyFilter)) {
            entries = [SELECT Product2Id, Product2.Name, Product2.ProductCode, Product2.Family, Product2.type__c, Product2.CAIRA_Level__c, UnitPrice FROM PricebookEntry WHERE IsActive = true];
        } else {
            entries = [SELECT Product2Id, Product2.Name, Product2.ProductCode, Product2.Family, Product2.type__c, Product2.CAIRA_Level__c, UnitPrice FROM PricebookEntry WHERE IsActive = true AND Product2.Family = :familyFilter];
        }

        for (PricebookEntry pbe : entries) {
            Decimal unitPrice = pbe.UnitPrice;

            if (isConvertedStudent && isCairaRecordType &&
                pbe.Product2 != null &&
                pbe.Product2.Family == RECORDTYPE_CAIRA &&
                pbe.Product2.CAIRA_Level__c == CAIRA_LEVEL_1) {
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

    @AuraEnabled(cacheable=true)
    public static Decimal getMinimumDownPayment(Id recordId) {
        String course;
        if (recordId == null) return 0;

        Schema.SObjectType sobType = recordId.getSObjectType();

        if (sobType == Lead__c.SObjectType) {
            Lead__c leadRec = [SELECT Course__c FROM Lead__c WHERE Id = :recordId LIMIT 1];
            course = leadRec.Course__c;
        } else {
            return 0;
        }

        if (String.isBlank(course)) return 0;

        List<Course_Down_Payment_Detail__mdt> rows = [SELECT Amount__c FROM Course_Down_Payment_Detail__mdt WHERE Course__c = :course LIMIT 1];

        System.debug('Course Down Payment Detail: ' +  rows[0].Amount__c);

        return rows.isEmpty() || rows[0].Amount__c == null ? 0 : rows[0].Amount__c;
    }

    @AuraEnabled(cacheable=true)
    public static Decimal getDiscountThreshold(Id recordId) {
        String course;
        if (recordId == null) return 0;

        Schema.SObjectType sobType = recordId.getSObjectType();

        if (sobType == Lead__c.SObjectType) {
            Lead__c leadRec = [SELECT Course__c FROM Lead__c WHERE Id = :recordId LIMIT 1];
            course = leadRec.Course__c;
        } else {
            return 0;
        }

        if (String.isBlank(course)) return 0;

        List<Course_Down_Payment_Detail__mdt> rows = [SELECT Discount__c FROM Course_Down_Payment_Detail__mdt WHERE Course__c = :course LIMIT 1];

        return rows.isEmpty() || rows[0].Discount__c == null ? 0 : rows[0].Discount__c;
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
            Account student = null;

            if (student == null && lead != null && lead.Student__c != null) {
                student = fetchStudentIfNeeded(lead.Student__c);
            }
            if (context != null && lead != null) {
                context.course = lead.Course__c;
            }

            Boolean requiresApproval = isDiscountApprovalRequired(context, lead, req);
            Callout_PurchaseOrderService.CalloutResult calloutRes;
            if (!requiresApproval) {
                // api callout to miles
              calloutRes = callExternalPurchaseService(req, lead, candidate);
            }

            Purchase_Order__c po    = createPurchaseOrder(req, context, lead, candidate, student);
            // po.Purchase_Order_Id__c = '41';
            if (calloutRes != null) {
                po.Purchase_Order_Id__c = String.valueOf(calloutRes.purchaseId);
                po.Response_Payload__c  = calloutRes.responseBody;
            }
            if (requiresApproval) {
                po.Approval_Status__c = STATUS_PENDING;
            }
            insert po;

            createLineItems(po.Id, req.items);
            updateCairaLevelIfNeeded(context, lead, req.items);
            createTransaction(po.Id, req.downPayment, req.leadId);
            if (!String.isBlank(req.loanId)) {
                createLoanTransaction(po.Id, req.loanId);
            }
            if (req.processingFee != null && req.processingFee > 0 && !String.isBlank(req.loanId)) {
                createProcessingFeeTransaction(po.Id, req.loanId, req.processingFee);
            }
            if (requiresApproval) {
                String course = context != null ? context.course : null;
                if (String.isBlank(course) && lead != null) {
                    course = lead.Course__c;
                }
                PurchasrOrderApprovalService.submitDiscountApprovalIfNeeded(
                    po.Id,
                    course,
                    req.leadId,
                    req.discount,
                    req.items,
                    req.approvalComments
                );
            }

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

                if (addressType == ADDRESS_TYPE_BILLING) {
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

            if (leadRec.Candidate__c != null) {
                Lead candidate = [SELECT Id FROM Lead WHERE Id = :leadRec.Candidate__c];

                if (addressType == ADDRESS_TYPE_BILLING) {
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
        txn.Status__c  = STATUS_INITIATED;
        txn.Is_Down_Payment__c = true;
        insert txn;
    }

    private static void createLoanTransaction(Id purchaseOrderId, Id loanId) {
        if (purchaseOrderId == null || loanId == null) return;

        Loan__c loan = [SELECT Amount_requested__c, loan_status__c FROM Loan__c WHERE Id = :loanId LIMIT 1];

        Transcation__c txn = new Transcation__c();
        txn.Purchase_Orders__c = purchaseOrderId;
        txn.Loan__c = loanId;
        txn.Payment__c = loan != null ? loan.Amount_requested__c : null;
        txn.Status__c = loan != null && loan.loan_status__c == 'Disbursed'
            ? 'Received'
            : STATUS_INITIATED;
        insert txn;
    }

    private static void createProcessingFeeTransaction(Id purchaseOrderId, Id loanId, Decimal feeAmount) {
        if (purchaseOrderId == null || loanId == null || feeAmount == null || feeAmount <= 0) return;

        Transcation__c txn = new Transcation__c();
        txn.Purchase_Orders__c = purchaseOrderId;
        txn.Loan__c = loanId;
        txn.Payment__c = feeAmount;
        txn.Status__c = 'Received';
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
        RecordContext context = new RecordContext(recordId);

        Schema.SObjectType sobType = recordId.getSObjectType();

        if (sobType == Lead__c.SObjectType) {
            // leadRecordId already set via constructor
        } else {
            throw new AuraHandledException('Unsupported record type for Purchase Order creation');
        }

        return context;
    }

    private static void validateAddress(RecordContext context, PurchaseOrderRequest req) {
        Boolean shippingRequired = hasStudyMaterial(req.items);


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

    private static Boolean hasStudyMaterial(List<LineItemRequest> items) {
        if (items == null) return false;

        for (LineItemRequest li : items) {
            if (li != null && li.learningType == LEARNING_TYPE_STUDY) {
                return true;
            }
        }
        return false;
    }

    private static Lead__c fetchLeadIfNeeded(Id leadRecordId) {
        Lead__c lead = [SELECT Id, Candidate__c, Course__c, Student__c, RecordTypeId FROM Lead__c WHERE Id = :leadRecordId LIMIT 1];
        if (leadRecordId == null) return null;


        if (lead.Candidate__c == null) {
            throw new AuraHandledException('Candidate is not linked to this Lead');
        }

        return lead;
    }

    private static Lead fetchCandidateIfNeeded(Lead__c lead) {
        List<Lead> candidates = [SELECT Street, City, State, PostalCode, Country, Shipping_Street__c, Shipping_City__c, Shipping_State__c, Shipping_Postal_Code__c, Shipping_Country__c,UUID__c FROM Lead WHERE Id = :lead.Candidate__c];
        if (lead == null) return null;


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

        po.Lead__c = context.leadRecordId;

        if (lead != null) {
            po.Candidate__c = lead.Candidate__c;
        }

        if (!String.isBlank(req.loanId)) {
            po.Loan__c = req.loanId;
        }

        po.Discount_Amount__c = req.discount;
        po.Phone_Number__c = req.phoneNumber;
        // po.Down_Payment__c = req.downPayment;
        po.Purchase_Order_Date__c = Date.today();

        setAddress(po, req.addressType, context, candidate, student);

        return po;
    }

    @AuraEnabled
    public static AddressDetailsDTO getAddressByRecordId(Id recordId) {
        AddressDetailsDTO res = new AddressDetailsDTO();
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required');
        }

        Schema.SObjectType sobType = recordId.getSObjectType();

        if (sobType == Lead__c.SObjectType) {
            Lead__c leadRec = [SELECT Candidate__c, Student__c FROM Lead__c WHERE Id = :recordId LIMIT 1];

            Lead candidate;
            if (leadRec.Candidate__c != null) {
                candidate = [SELECT Street, City, State, PostalCode, Country, Shipping_Street__c, Shipping_City__c, Shipping_State__c, Shipping_Postal_Code__c, Shipping_Country__c, Phone FROM Lead WHERE Id = :leadRec.Candidate__c];
            }

            if (leadRec.Student__c != null) {
                Account acc = [SELECT BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry, ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry, Phone FROM Account WHERE Id = :leadRec.Student__c];

                res.billing.put('street', acc.BillingStreet);
                res.billing.put('city', acc.BillingCity);
                res.billing.put('state', acc.BillingState);
                res.billing.put('postal', acc.BillingPostalCode);
                res.billing.put('country', acc.BillingCountry);
                res.phone = acc.Phone;

            } else if (candidate != null) {
                res.billing.put('street', candidate.Street);
                res.billing.put('city', candidate.City);
                res.billing.put('state', candidate.State);
                res.billing.put('postal', candidate.PostalCode);
                res.billing.put('country', candidate.Country);
                res.phone = candidate.Phone;
            }

            if (candidate != null) {
                res.shipping.put('street', candidate.Shipping_Street__c);
                res.shipping.put('city', candidate.Shipping_City__c);
                res.shipping.put('state', candidate.Shipping_State__c);
                res.shipping.put('postal', candidate.Shipping_Postal_Code__c);
                res.shipping.put('country', candidate.Shipping_Country__c);
            } else if (leadRec.Student__c != null) {
                Account accShip = [SELECT ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry FROM Account WHERE Id = :leadRec.Student__c];
                res.shipping.put('street', accShip.ShippingStreet);
                res.shipping.put('city', accShip.ShippingCity);
                res.shipping.put('state', accShip.ShippingState);
                res.shipping.put('postal', accShip.ShippingPostalCode);
                res.shipping.put('country', accShip.ShippingCountry);
            }

            return res;
        }

        throw new AuraHandledException('Unsupported record type');
    }

    private static void setAddress(
        Purchase_Order__c po,
        String addressType,
        RecordContext context,
        Lead candidate,
        Account student
    ) {
        if (student != null && context.leadRecordId != null) {
            if (addressType == ADDRESS_TYPE_BILLING) {
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
            if (addressType == ADDRESS_TYPE_BILLING) {
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

        if (!lines.isEmpty()) {
            insert lines;
        }
    }

    @AuraEnabled
    public static Boolean checkLeadAddress(Id leadRecordId) {
        Lead__c leadRec = [SELECT Candidate__c FROM Lead__c WHERE Id = :leadRecordId LIMIT 1];
        Lead candidate = [SELECT Street, City, State, PostalCode, Country, Shipping_Street__c, Shipping_City__c, Shipping_State__c, Shipping_Postal_Code__c, Shipping_Country__c FROM Lead WHERE Id = :leadRec.Candidate__c LIMIT 1];

        if (leadRec.Candidate__c == null) {
            throw new AuraHandledException('Candidate is not linked to this Lead');
        }


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

    @AuraEnabled(cacheable=true)
    public static List<Loan__c> getLoansForLead(Id recordId) {
        if (recordId == null) return new List<Loan__c>();
        return [SELECT Id, Name, Loan_Provider__c, loan_status__c, application_id__c, Loan_Id__c, Tenure__c FROM Loan__c WHERE Lead__c = :recordId AND loan_status__c IN ('Approved')];
    }

    @AuraEnabled
    public static AddressStatusDTO checkAddressByRecordId(Id recordId) {
        AddressStatusDTO res = new AddressStatusDTO();
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required');
        }

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

        throw new AuraHandledException('Unsupported record type');
    }

    private static Boolean hasCompleteAddress(
        String street, String city, String state, String postalCode, String country
    ) {
        return !String.isBlank(street) && !String.isBlank(city);
    }

    private static Callout_PurchaseOrderService.CalloutResult callExternalPurchaseService( PurchaseOrderRequest req, Lead__c lead, Lead candidate ) {

        List<SimpleLineItem> baseItems = new List<SimpleLineItem>();
        for (LineItemRequest li : req.items) {
            if (li != null && li.productId != null) {
                baseItems.add(new SimpleLineItem(li.productId, li.unitPrice, li.qty));
            }
        }
        List<ExpandedProduct> expandedItems = expandBundleItems(baseItems);
        List<ExpandedProduct> enrolmentItems = buildImmediateOptionItems(baseItems);

        Callout_PurchaseOrderService.Request extReq = new Callout_PurchaseOrderService.Request();
        extReq.source       = SOURCE_SF;
        extReq.sf_id        = String.valueOf(candidate.Id);
        extReq.sf_lead_id   = String.valueOf(req.leadId);
        extReq.uuid         = candidate.UUID__c;
        extReq.down_payment = req.downPayment;
        //extReq.created_by   = UserInfo.getName();
        extReq.created_by   = CREATED_BY_DEFAULT;

        Callout_PurchaseOrderService.RequestItem item = new Callout_PurchaseOrderService.RequestItem();
        item.program = (lead != null ? String.valueOf(lead.Course__c) : null);
        Boolean hasTraining = false;
        Boolean hasStudyMaterial = false;

        item.skus = new List<String>();
        item.enrolment_line_items = new List<Callout_PurchaseOrderService.EnrolmentLineItem>();

        Decimal total = 0;

        for (LineItemRequest li : req.items) {
            if (li == null) continue;

            if (!String.isBlank(li.learningType)) {
                if (li.learningType == LEARNING_TYPE_TRAINING) hasTraining = true;
                if (li.learningType == LEARNING_TYPE_STUDY) hasStudyMaterial = true;
            }
        }

        Set<String> seenSkus = new Set<String>();
        for (ExpandedProduct ep : expandedItems) {
            if (ep == null) continue;
            if (!String.isBlank(ep.sku) && !seenSkus.contains(ep.sku)) {
                item.skus.add(ep.sku);
                seenSkus.add(ep.sku);
            }
        }

        for (ExpandedProduct ep : enrolmentItems) {
            if (ep == null) continue;
            Callout_PurchaseOrderService.EnrolmentLineItem eli =
                new Callout_PurchaseOrderService.EnrolmentLineItem();

            eli.item_name = !String.isBlank(ep.name) ? ep.name : 'Item';

            Decimal lineAmount =
                (ep.unitPrice != null ? ep.unitPrice : 0) *
                (ep.qty != null ? ep.qty : 0);

            eli.price          = lineAmount;
            eli.price_with_gst = lineAmount;
            eli.discound       = 0;
            eli.final_price    = lineAmount;

            item.enrolment_line_items.add(eli);
            total += lineAmount;
        }

        item.has_training       = hasTraining;
        item.has_study_material = hasStudyMaterial;

        Decimal discountAmount = req.discount == null ? 0 : req.discount;
        item.actual_price = total;
        item.agreed_fee   = Math.max(0, total - discountAmount);
        item.discount     = discountAmount;
        
        if (!String.isBlank(req.loanId)) {
            try {
                // req.loanId is the Salesforce Id of the Loan record from LWC
                List<Loan__c> loans = [SELECT Loan_Id__c FROM Loan__c WHERE Id = :req.loanId LIMIT 1];
                if (!loans.isEmpty() && !String.isBlank(loans[0].Loan_Id__c)) {
                    String loanIdRaw = loans[0].Loan_Id__c;
                    try {
                        item.loan_id = Integer.valueOf(loanIdRaw);
                    } catch (Exception ex) {
                        try {
                            Decimal loanDec = Decimal.valueOf(loanIdRaw);
                            item.loan_id = loanDec != null ? Integer.valueOf(loanDec) : null;
                        } catch (Exception ex2) {
                            item.loan_id = null;
                        }
                    }
                } else {
                    item.loan_id = null;
                }
            } catch (Exception e) {
                System.debug('Failed to fetch loan info: ' + e.getMessage());
                item.loan_id = null;
            }
        } else {
            item.loan_id = null;
        }

        extReq.purchase_items =
            new List<Callout_PurchaseOrderService.RequestItem>{ item };

        Callout_PurchaseOrderService.CalloutResult result = Callout_PurchaseOrderService.createPurchase(extReq);

        if (result == null || result.purchaseId == null) {
            throw new AuraHandledException('External service did not return purchase_id. Purchase Order not created.');
        }

        return result;
    }

    public static List<ExpandedProduct> expandBundleItems(List<SimpleLineItem> items) {
        List<ExpandedProduct> result = new List<ExpandedProduct>();
        if (items == null || items.isEmpty()) return result;

        Set<Id> seedIds = new Set<Id>();
        for (SimpleLineItem li : items) {
            if (li != null && li.productId != null) seedIds.add(li.productId);
        }
        if (seedIds.isEmpty()) return result;

        Map<Id, Product2> prodMap = new Map<Id, Product2>([
            SELECT Id, Name, ProductCode, Is_Bundle__c
            FROM Product2
            WHERE Id IN :seedIds
        ]);

        Map<Id, List<Product_Option__c>> optionsByBundle = buildOptionsByBundle(seedIds, prodMap);

        for (SimpleLineItem li : items) {
            if (li == null || li.productId == null) continue;
            expandItemRecursive(
                li.productId,
                li.qty != null ? li.qty : 0,
                li.unitPrice,
                prodMap,
                optionsByBundle,
                result,
                new Set<Id>()
            );
        }

        return result;
    }

    public static List<ExpandedProduct> buildImmediateOptionItems(List<SimpleLineItem> items) {
        List<ExpandedProduct> result = new List<ExpandedProduct>();
        if (items == null || items.isEmpty()) return result;

        Set<Id> seedIds = new Set<Id>();
        for (SimpleLineItem li : items) {
            if (li != null && li.productId != null) seedIds.add(li.productId);
        }
        if (seedIds.isEmpty()) return result;

        Map<Id, Product2> prodMap = new Map<Id, Product2>([SELECT Id, Name, ProductCode, Is_Bundle__c FROM Product2 WHERE Id IN :seedIds]);
        Map<Id, List<Product_Option__c>> optionsByBundle = new Map<Id, List<Product_Option__c>>();

        List<Product_Option__c> options = [SELECT Id, Bundle_Product__c, Product__c, Qty__c, Unit_Price__c FROM Product_Option__c WHERE Bundle_Product__c IN :seedIds];
        Set<Id> childIds = new Set<Id>();
        for (Product_Option__c opt : options) {
            if (opt.Bundle_Product__c == null) continue;
            if (!optionsByBundle.containsKey(opt.Bundle_Product__c)) {
                optionsByBundle.put(opt.Bundle_Product__c, new List<Product_Option__c>());
            }
            optionsByBundle.get(opt.Bundle_Product__c).add(opt);
            if (opt.Product__c != null) childIds.add(opt.Product__c);
        }

        if (!childIds.isEmpty()) {
            for (Product2 p : [SELECT Id, Name, ProductCode, Is_Bundle__c FROM Product2 WHERE Id IN :childIds]) {
                prodMap.put(p.Id, p);
            }
        }

        for (SimpleLineItem li : items) {
            if (li == null || li.productId == null) continue;
            Product2 p = prodMap.get(li.productId);
            if (p != null && p.Is_Bundle__c && optionsByBundle.containsKey(li.productId)) {
                for (Product_Option__c opt : optionsByBundle.get(li.productId)) {
                    Product2 child = prodMap.get(opt.Product__c);
                    if (child == null) continue;
                    Decimal childQty = (opt.Qty__c != null ? opt.Qty__c : 1);
                    Decimal effectiveQty = (li.qty != null ? li.qty : 0) * childQty;
                    result.add(new ExpandedProduct(
                        child.Id,
                        child.Name,
                        child.ProductCode,
                        opt.Unit_Price__c,
                        effectiveQty
                    ));
                }
            } else {
                result.add(new ExpandedProduct(
                    li.productId,
                    p != null ? p.Name : null,
                    p != null ? p.ProductCode : null,
                    li.unitPrice,
                    li.qty
                ));
            }
        }

        return result;
    }

    private static Map<Id, List<Product_Option__c>> buildOptionsByBundle(
        Set<Id> seedIds,
        Map<Id, Product2> prodMap
    ) {
        Map<Id, List<Product_Option__c>> optionsByBundle = new Map<Id, List<Product_Option__c>>();
        Set<Id> toProcess = new Set<Id>();
        for (Id pid : seedIds) {
            Product2 p = prodMap.get(pid);
            if (p != null && p.Is_Bundle__c) toProcess.add(pid);
        }

        Set<Id> processed = new Set<Id>();
        Integer guard = 0;

        while (!toProcess.isEmpty() && guard < 10) {
            guard++;
            Set<Id> current = new Set<Id>(toProcess);
            toProcess.clear();

            List<Product_Option__c> options = [
                SELECT Id, Bundle_Product__c, Product__c, Qty__c, Unit_Price__c
                FROM Product_Option__c
                WHERE Bundle_Product__c IN :current
            ];

            Set<Id> childIds = new Set<Id>();
            for (Product_Option__c opt : options) {
                if (opt.Bundle_Product__c == null) continue;
                if (!optionsByBundle.containsKey(opt.Bundle_Product__c)) {
                    optionsByBundle.put(opt.Bundle_Product__c, new List<Product_Option__c>());
                }
                optionsByBundle.get(opt.Bundle_Product__c).add(opt);
                if (opt.Product__c != null) childIds.add(opt.Product__c);
            }

            if (!childIds.isEmpty()) {
                Set<Id> missing = new Set<Id>();
                for (Id cid : childIds) if (!prodMap.containsKey(cid)) missing.add(cid);
                if (!missing.isEmpty()) {
                    for (Product2 p : [
                        SELECT Id, Name, ProductCode, Is_Bundle__c
                        FROM Product2
                        WHERE Id IN :missing
                    ]) {
                        prodMap.put(p.Id, p);
                    }
                }
            }

            for (Id cid : childIds) {
                Product2 cp = prodMap.get(cid);
                if (cp != null && cp.Is_Bundle__c && !processed.contains(cid)) {
                    toProcess.add(cid);
                }
            }

            processed.addAll(current);
        }

        return optionsByBundle;
    }

    private static void expandItemRecursive(
        Id productId,
        Decimal qty,
        Decimal unitPrice,
        Map<Id, Product2> prodMap,
        Map<Id, List<Product_Option__c>> optionsByBundle,
        List<ExpandedProduct> out,
        Set<Id> path
    ) {
        if (productId == null || qty == null || qty <= 0) return;
        if (path.contains(productId)) return;
        path.add(productId);

        Product2 prod = prodMap.get(productId);
        if (prod == null) {
            path.remove(productId);
            return;
        }

        List<Product_Option__c> opts = optionsByBundle.get(productId);
        if (prod.Is_Bundle__c && opts != null && !opts.isEmpty()) {
            for (Product_Option__c opt : opts) {
                Id childId = opt.Product__c;
                if (childId == null) continue;
                Decimal childQty = (opt.Qty__c != null ? opt.Qty__c : 1);
                Decimal effectiveQty = qty * childQty;
                Decimal childUnitPrice = opt.Unit_Price__c;
                expandItemRecursive(
                    childId,
                    effectiveQty,
                    childUnitPrice,
                    prodMap,
                    optionsByBundle,
                    out,
                    path
                );
            }
            path.remove(productId);
            return;
        }

        out.add(new ExpandedProduct(
            productId,
            prod.Name,
            prod.ProductCode,
            unitPrice,
            qty
        ));
        path.remove(productId);
    }

    private class RecordContext {
        public Id leadRecordId;
        public String course;

        public RecordContext(Id leadRecordId) {
            this.leadRecordId = leadRecordId;
        }
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
        if (recordTypeName != RECORDTYPE_CAIRA) return;

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

            if (p.CAIRA_Level__c == CAIRA_LEVEL_1) hasLevel1 = true;
            if (p.CAIRA_Level__c == CAIRA_LEVEL_2) hasLevel2 = true;
            if (p.CAIRA_Level__c == CAIRA_LEVEL_3) hasLevel3 = true;
        }

        List<String> levels = new List<String>();
        if (hasLevel1) levels.add(CAIRA_LEVEL_1);
        if (hasLevel2) levels.add(CAIRA_LEVEL_2);
        if (hasLevel3) levels.add(CAIRA_LEVEL_3);
        if (levels.isEmpty()) return;

        Lead__c upd = new Lead__c(
            Id = context.leadRecordId,
            Caira_Level__c = String.join(levels, ';')
        );
        update upd;
    }

    private static Boolean isDiscountApprovalRequired(
        RecordContext context,
        Lead__c lead,
        PurchaseOrderRequest req
    ) {
        if (req == null) return false;

        String course = context != null ? context.course : null;
        if (String.isBlank(course) && lead != null) {
            course = lead.Course__c;
        }
        if (String.isBlank(course)) return false;

        Decimal thresholdPercent = getDiscountThreshold(course);
        if (thresholdPercent == null || thresholdPercent <= 0) return false;

        Decimal subtotal = calculateSubTotal(req.items);
        if (subtotal <= 0) return false;

        Decimal discountAmount = req.discount == null ? 0 : req.discount;
        Decimal discountPercent = (discountAmount / subtotal) * 100;

        return discountPercent > thresholdPercent;
    }

    private static Decimal calculateSubTotal(List<LineItemRequest> items) {
        Decimal total = 0;
        if (items == null) return 0;
        for (LineItemRequest li : items) {
            if (li == null) continue;
            Decimal unit = li.unitPrice == null ? 0 : li.unitPrice;
            Decimal qty = li.qty == null ? 0 : li.qty;
            total += unit * qty;
        }
        return total;
    }

    private static Decimal getDiscountThreshold(String course) {
        List<Course_Down_Payment_Detail__mdt> rows = [SELECT Discount__c FROM Course_Down_Payment_Detail__mdt WHERE Course__c = :course LIMIT 1];
        if (String.isBlank(course)) return null;


        if (rows.isEmpty() || rows[0].Discount__c == null) return null;
        return rows[0].Discount__c;
    }

}