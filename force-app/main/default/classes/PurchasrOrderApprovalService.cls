public without sharing class PurchasrOrderApprovalService {

    public static void submitDiscountApprovalIfNeeded(
        Id purchaseOrderId,
        String course,
        Id leadId,
        Decimal discountAmount,
        List<PurchaseOrderService.LineItemRequest> items,
        String approvalComments
    ) {
        if (purchaseOrderId == null || items == null) return;
        if (String.isBlank(course)) return;

        Decimal thresholdPercent = getDiscountThreshold(course);
        if (thresholdPercent == null) return;

        Decimal subtotal = calculateSubTotal(items);
        if (subtotal <= 0) return;

        Decimal discountAmt = discountAmount == null ? 0 : discountAmount;
        Decimal discountPercent = (discountAmt / subtotal) * 100;
        if (discountPercent <= thresholdPercent) return;

        String comment = approvalComments;
        if (String.isBlank(comment)) {
            comment = 'Discount ' + discountPercent.setScale(2) + '% exceeds allowed ' +
                thresholdPercent.setScale(2) + '%';
        } else {
            comment = comment.trim() + ' | Discount ' + discountPercent.setScale(2) + '% exceeds allowed ' +
                thresholdPercent.setScale(2) + '%';
        }

        Id approverId = getLeadOwnersManagerManager(leadId);

        Approval.ProcessSubmitRequest approvalReq = new Approval.ProcessSubmitRequest();
        approvalReq.setObjectId(purchaseOrderId);
        approvalReq.setProcessDefinitionNameOrId('Purchase_Order_Discount_Approval');
        if (approverId != null) {
            approvalReq.setNextApproverIds(new Id[] { approverId });
        }
        approvalReq.setComments(comment);

        Approval.ProcessResult result = Approval.process(approvalReq);

        if (result != null && result.isSuccess() && approverId != null) {
            sendApprovalRequestEmail(purchaseOrderId, approverId);
        }
    }

    public static void enqueuePurchaseOrderCallout(Set<Id> purchaseOrderIds) {
        if (purchaseOrderIds == null || purchaseOrderIds.isEmpty()) return;
        System.enqueueJob(new PurchaseOrderApprovalCalloutQueueable(new List<Id>(purchaseOrderIds)));
    }

    public class PurchaseOrderApprovalCalloutQueueable implements Queueable, Database.AllowsCallouts {
        private List<Id> purchaseOrderIds;

        public PurchaseOrderApprovalCalloutQueueable(List<Id> purchaseOrderIds) {
            this.purchaseOrderIds = purchaseOrderIds;
        }

        public void execute(QueueableContext context) {
            List<Purchase_Order__c> pos = [SELECT Id, Lead__c, Candidate__c, Discount_Amount__c, Purchase_Order_Id__c, Response_Payload__c, Approval_Status__c FROM Purchase_Order__c WHERE Id IN :purchaseOrderIds];
            Set<Id> leadIds = new Set<Id>();
            Set<Id> candidateIds = new Set<Id>();
            List<Purchase_Order_Line_Item__c> lines = [SELECT Id, Purchase_Order__c, Product__c, Quantity__c, Unit_Price__c FROM Purchase_Order_Line_Item__c WHERE Purchase_Order__c IN :purchaseOrderIds];
            Map<Id, List<Purchase_Order_Line_Item__c>> linesByPo = new Map<Id, List<Purchase_Order_Line_Item__c>>();
            Set<Id> productIds = new Set<Id>();
            Map<Id, Decimal> downPayments = new Map<Id, Decimal>();
            List<Purchase_Order__c> toUpdate = new List<Purchase_Order__c>();
            if (purchaseOrderIds == null || purchaseOrderIds.isEmpty()) return;


            for (Purchase_Order__c po : pos) {
                if (po.Lead__c != null) leadIds.add(po.Lead__c);
                if (po.Candidate__c != null) candidateIds.add(po.Candidate__c);
            }

            Map<Id, Lead__c> leadMap = leadIds.isEmpty()
                ? new Map<Id, Lead__c>()
                : new Map<Id, Lead__c>([SELECT Id, Course__c FROM Lead__c WHERE Id IN :leadIds]);

            Map<Id, Lead> candidateMap = candidateIds.isEmpty()
                ? new Map<Id, Lead>()
                : new Map<Id, Lead>([SELECT Id, UUID__c FROM Lead WHERE Id IN :candidateIds]);


            for (Purchase_Order_Line_Item__c line : lines) {
                if (!linesByPo.containsKey(line.Purchase_Order__c)) {
                    linesByPo.put(line.Purchase_Order__c, new List<Purchase_Order_Line_Item__c>());
                }
                linesByPo.get(line.Purchase_Order__c).add(line);
                if (line.Product__c != null) productIds.add(line.Product__c);
            }

            Map<Id, Product2> productMap = productIds.isEmpty()
                ? new Map<Id, Product2>()
                : new Map<Id, Product2>([SELECT Id, Name, ProductCode, Type__c FROM Product2 WHERE Id IN :productIds]);

            for (AggregateResult ar : [SELECT Purchase_Orders__c poId, SUM(Payment__c) total FROM Transcation__c WHERE Purchase_Orders__c IN :purchaseOrderIds AND Is_Down_Payment__c = true GROUP BY Purchase_Orders__c]) {
                downPayments.put((Id) ar.get('poId'), (Decimal) ar.get('total'));
            }


            for (Purchase_Order__c po : pos) {
                if (po.Approval_Status__c != 'Approved') continue;
                if (po.Purchase_Order_Id__c != null) continue;

                Lead__c lead = leadMap.get(po.Lead__c);
                Lead candidate = candidateMap.get(po.Candidate__c);
                if (lead == null || candidate == null) continue;

                Callout_PurchaseOrderService.Request extReq = new Callout_PurchaseOrderService.Request();
                extReq.source       = 'sf';
                extReq.sf_id        = String.valueOf(lead.Id);
                // extReq.sf_lead_id   = String.valueOf(lead.Id);
                extReq.uuid         = candidate.UUID__c;
                extReq.down_payment = downPayments.containsKey(po.Id) ? downPayments.get(po.Id) : 0;
                extReq.created_by   = 'MPE226';

                Callout_PurchaseOrderService.RequestItem item = new Callout_PurchaseOrderService.RequestItem();
                item.program = lead.Course__c;
                item.skus = new List<String>();
                item.enrolment_line_items = new List<Callout_PurchaseOrderService.EnrolmentLineItem>();

                Boolean hasTraining = false;
                Boolean hasStudyMaterial = false;
                Decimal total = 0;

                List<Purchase_Order_Line_Item__c> poLines = linesByPo.get(po.Id);
                if (poLines == null || poLines.isEmpty()) continue;

                for (Purchase_Order_Line_Item__c line : poLines) {
                    Product2 p = productMap.get(line.Product__c);
                    if (p != null && p.Type__c == 'Training') hasTraining = true;
                    if (p != null && p.Type__c == 'Study Material') hasStudyMaterial = true;
                }

                List<PurchaseOrderService.SimpleLineItem> baseItems = new List<PurchaseOrderService.SimpleLineItem>();
                for (Purchase_Order_Line_Item__c line : poLines) {
                    if (line.Product__c == null) continue;
                    baseItems.add(new PurchaseOrderService.SimpleLineItem(
                        line.Product__c,
                        line.Unit_Price__c,
                        line.Quantity__c
                    ));
                }

                List<PurchaseOrderService.ExpandedProduct> expandedItems =
                    PurchaseOrderService.expandBundleItems(baseItems);
                List<PurchaseOrderService.ExpandedProduct> enrolmentItems =
                    PurchaseOrderService.buildImmediateOptionItems(baseItems);

                Set<String> seenSkus = new Set<String>();
                for (PurchaseOrderService.ExpandedProduct ep : expandedItems) {
                    if (ep == null) continue;
                    if (!String.isBlank(ep.sku) && !seenSkus.contains(ep.sku)) {
                        item.skus.add(ep.sku);
                        seenSkus.add(ep.sku);
                    }
                }

                for (PurchaseOrderService.ExpandedProduct ep : enrolmentItems) {
                    if (ep == null) continue;
                    Decimal lineAmount =
                        (ep.unitPrice != null ? ep.unitPrice : 0) *
                        (ep.qty != null ? ep.qty : 0);

                    Callout_PurchaseOrderService.EnrolmentLineItem eli =
                        new Callout_PurchaseOrderService.EnrolmentLineItem();
                    eli.item_name = !String.isBlank(ep.name) ? ep.name : 'Item';
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
                item.discount     = po.Discount_Amount__c;
                item.loan_id      = null;

                extReq.purchase_items = new List<Callout_PurchaseOrderService.RequestItem>{ item };

                Callout_PurchaseOrderService.CalloutResult result =
                    Callout_PurchaseOrderService.createPurchase(extReq);

                if (result != null && result.purchaseId != null) {
                    toUpdate.add(new Purchase_Order__c(
                        Id = po.Id,
                        Purchase_Order_Id__c = String.valueOf(result.purchaseId),
                        Response_Payload__c = result.responseBody
                    ));

                    sendApprovalApprovedEmail(po.Id, po.Lead__c);
                }
            }

            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
        }
    }

    private static Id getLeadOwnersManagerManager(Id leadId) {
        Lead__c leadRec = [SELECT OwnerId FROM Lead__c WHERE Id = :leadId LIMIT 1];
        User ownerUser = [SELECT ManagerId FROM User WHERE Id = :leadRec.OwnerId LIMIT 1];
        if (leadId == null) return null;



        if (ownerUser.ManagerId != null) {
            return ownerUser.ManagerId;
        }

        return null;
    }

    private static Decimal calculateSubTotal(List<PurchaseOrderService.LineItemRequest> items) {
        Decimal total = 0;
        if (items == null) return 0;
        for (PurchaseOrderService.LineItemRequest li : items) {
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

    private static void sendApprovalRequestEmail(Id poId, Id approverId) {
        EmailTemplate template = [SELECT Id FROM EmailTemplate WHERE DeveloperName = 'approval_request_email' LIMIT 1];

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTemplateId(template.Id);
        // REQUIRED when using template
        mail.setTargetObjectId(approverId);
        mail.setSaveAsActivity(false);

        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    private static void sendApprovalApprovedEmail(Id poId, Id leadId) {
        Purchase_Order__c po = [SELECT Id, CreatedById FROM Purchase_Order__c WHERE Id = :poId LIMIT 1];
        User approverUser = [SELECT Id, Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        EmailTemplate template = [SELECT Id FROM EmailTemplate WHERE DeveloperName = 'approval_approved_email' LIMIT 1];



        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTemplateId(template.Id);
        mail.setTargetObjectId(po.CreatedById);
        mail.setWhatId(poId);
        mail.setSaveAsActivity(false);

        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }
}
