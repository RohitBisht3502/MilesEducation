public without sharing class LeadTransferController {

    private static final Set<String> ALLOWED_NAMES = new Set<String>{ 'CC', 'SR' };

    public class UserAccessWrapper {
        @AuraEnabled public Boolean hasAccess;
        @AuraEnabled public String message;
    }

    public class TransferValidationWrapper {
        @AuraEnabled public Boolean hasPendingRequest;
        @AuraEnabled public String message;
    }

    @AuraEnabled(cacheable=true)
    public static UserAccessWrapper getUserAccessInfo() {
        User currentUser = [
            SELECT Id, Profile.Name, UserRole.DeveloperName
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        UserAccessWrapper wrapper = new UserAccessWrapper();
        wrapper.hasAccess =
            ALLOWED_NAMES.contains(currentUser.Profile != null ? currentUser.Profile.Name : null) ||
            ALLOWED_NAMES.contains(currentUser.UserRole != null ? currentUser.UserRole.DeveloperName : null);
        wrapper.message = wrapper.hasAccess
            ? null
            : 'You do not have access. Only CC and SR users can transfer leads.';
        return wrapper;
    }

    @AuraEnabled(cacheable=true)
    public static TransferValidationWrapper getTransferValidationInfo(Id leadId) {
        validateTransferAccess();

        TransferValidationWrapper wrapper = new TransferValidationWrapper();
        wrapper.hasPendingRequest = false;

        if (leadId == null) {
            return wrapper;
        }

        List<Approval_Process__c> pendingRequests = [SELECT Id FROM Approval_Process__c WHERE Merge_Status__c = 'Pending' AND Record_Type__c = 'Lead Transfer Request' AND Master_Lead__c = :leadId LIMIT 1];

        if (!pendingRequests.isEmpty()) {
            wrapper.hasPendingRequest = true;
            wrapper.message = 'One process already exists for this lead transfer.';
        }

        return wrapper;
    }

    @AuraEnabled
    public static void sendApproval(Id leadId, String comments) {
        validateTransferAccess();

        Id currentUserId = UserInfo.getUserId();
        Lead ld = [SELECT Id, OwnerId FROM Lead WHERE Id = :leadId LIMIT 1];
        
         if (ld.OwnerId == currentUserId) {
            throw new AuraHandledException('You cannot transfer this lead because you are the current owner of the candidate.');
        }

        TransferValidationWrapper validation = getTransferValidationInfo(leadId);
        if (validation != null && validation.hasPendingRequest) {
            throw new AuraHandledException(validation.message);
        }

        // Fetch Managers for both Lead Owner and current Requestor
        Set<Id> userIds = new Set<Id>{ld.OwnerId, currentUserId};
        Map<Id, User> userMap = new Map<Id, User>([SELECT Id, ManagerId FROM User WHERE Id IN :userIds]);

        User leadOwner = userMap.get(ld.OwnerId);
        User requestor = userMap.get(currentUserId);

        Id approverId = getAdminIdFromLabel();

        if (requestor != null && requestor.ManagerId != null && ld.OwnerId == requestor.ManagerId) {
            approverId = requestor.ManagerId;
        } else if (leadOwner != null && requestor != null &&
            leadOwner.ManagerId != null && leadOwner.ManagerId == requestor.ManagerId) {
            approverId = leadOwner.ManagerId;
        }

        Id recordTypeId = Schema.SObjectType.Approval_Process__c.getRecordTypeInfosByDeveloperName().get('Lead_Transfer_Request').getRecordTypeId();

        Approval_Process__c req = new Approval_Process__c();

        req.Master_Lead__c = leadId;
        req.Requestor__c = currentUserId;
        req.Approver__c = approverId;
        req.OwnerId = approverId;
        req.Comments__c = comments;
        req.Merge_Status__c = 'Pending';
        req.Record_Type__c = 'Lead Transfer Request';
        req.RecordTypeId = recordTypeId;

        insert req;
        sendApprovalNotification(req.Id, approverId);

        // CREATE INITIAL LOG
        insert new Activity_log__c(
            Name = 'Lead Transfer Request',
            Candidate__c = leadId,
            Activity_Type__c = 'Owner Change',
            Description__c = 'Lead Transfer Request initiated. Status: Pending approval.',
            Previous_Owner__c = ld.OwnerId,
            New_Owner__c = currentUserId,
            Logging_Id__c = req.Id,
            Action_Performed_By__c = currentUserId
        );
    }

    private static void sendApprovalNotification(Id processId, Id targetUserId) {
        if (processId == null || targetUserId == null) {
            return;
        }

        List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'Custom_Notification' LIMIT 1];

        if (types.isEmpty()) {
            return;
        }

        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setNotificationTypeId(types[0].Id);
        notification.setTargetId(processId);
        notification.setTitle('Lead Transfer Approval Request');
        notification.setBody('A new lead transfer request is pending your approval.');
        notification.send(new Set<String>{ String.valueOf(targetUserId) });
    }

    private static void validateTransferAccess() {
        UserAccessWrapper access = getUserAccessInfo();
        if (access == null || access.hasAccess != true) {
            throw new AuraHandledException('You do not have access. Only CC and SR users can transfer leads.');
        }
    }

    private static Id getAdminIdFromLabel() {
        String adminUsername = Label.Admin_Username;
        if (String.isBlank(adminUsername)) {
            throw new AuraHandledException('Custom label Admin_Username is blank.');
        }

        List<User> adminUsers = [SELECT Id FROM User WHERE Username = :adminUsername AND IsActive = true LIMIT 1];

        if (adminUsers.isEmpty()) {
            throw new AuraHandledException('No active user found for Admin_Username label value: ' + adminUsername);
        }

        return adminUsers[0].Id;
    }
}