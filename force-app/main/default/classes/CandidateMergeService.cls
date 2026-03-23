public without sharing class CandidateMergeService {

    public class MergeRequest {
        public Id sourceCandidateId;
        public Id targetCandidateId;
        public String mergeComments;

        public MergeRequest(Id sourceCandidateId, Id targetCandidateId, String mergeComments) {
            this.sourceCandidateId = sourceCandidateId;
            this.targetCandidateId = targetCandidateId;
            this.mergeComments = mergeComments;
        }
    }

    @TestVisible
    private static final List<String> RELATED_OBJECT_API_NAMES = new List<String>{
        'Lead__c',
        'Email__c',
        'Phone_Number__c',
        'Call_Log__c',
        'Enquiry__c'
    };

    public static void mergeCandidates(Id sourceCandidateId, Id targetCandidateId, String mergeComments) {
        mergeCandidates(new List<MergeRequest>{
            new MergeRequest(sourceCandidateId, targetCandidateId, mergeComments)
        });
    }

    public static void mergeCandidates(List<MergeRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Map<Id, Id> sourceToTargetCandidateId = new Map<Id, Id>();
        Map<Id, String> mergeCommentsByTargetId = new Map<Id, String>();
        Set<Id> allCandidateIds = new Set<Id>();

        for (MergeRequest request : requests) {
            validateInputs(request.sourceCandidateId, request.targetCandidateId);
            sourceToTargetCandidateId.put(request.sourceCandidateId, request.targetCandidateId);
            allCandidateIds.add(request.sourceCandidateId);
            allCandidateIds.add(request.targetCandidateId);
            if (String.isNotBlank(request.mergeComments)) {
                mergeCommentsByTargetId.put(request.targetCandidateId, request.mergeComments);
            }
        }

        Map<Id, Lead> candidateById = new Map<Id, Lead>([
            SELECT Id, Phone, MobilePhone, Email, Candidate__c, Is_Merged__c, Merge_Comments__c
            FROM Lead
            WHERE Id IN :allCandidateIds
        ]);
        Map<Id, String> sourcePhoneByCandidateId = getSourcePhoneByCandidateId(sourceToTargetCandidateId.keySet());
        Map<Id, String> sourceEmailByCandidateId = getSourceEmailByCandidateId(sourceToTargetCandidateId.keySet());

        for (MergeRequest request : requests) {
            if (!candidateById.containsKey(request.sourceCandidateId) || !candidateById.containsKey(request.targetCandidateId)) {
                throw new AuraHandledException('Both source and target candidates must exist.');
            }
        }

        reparentRelatedRecords(sourceToTargetCandidateId);

        Set<Id> targetCandidateIds = new Set<Id>();
        Map<Id, Lead> sourceUpdatesById = new Map<Id, Lead>();
        Map<Id, Lead> targetUpdatesById = new Map<Id, Lead>();
        for (MergeRequest request : requests) {
            Lead sourceCandidate = candidateById.get(request.sourceCandidateId);
            Lead targetCandidate = candidateById.get(request.targetCandidateId);

            sourceUpdatesById.put(request.sourceCandidateId, new Lead(
                Id = request.sourceCandidateId,
                Candidate__c = request.targetCandidateId,
                Is_Merged__c = true
            ));

            Lead targetUpdate = buildTargetCandidateUpdate(
                sourceCandidate,
                targetCandidate,
                targetUpdatesById.get(request.targetCandidateId),
                sourcePhoneByCandidateId.get(request.sourceCandidateId),
                sourceEmailByCandidateId.get(request.sourceCandidateId),
                mergeCommentsByTargetId.get(request.targetCandidateId)
            );
            if (targetUpdate != null) {
                targetUpdatesById.put(request.targetCandidateId, targetUpdate);
            }
            targetCandidateIds.add(request.targetCandidateId);
        }

        List<Lead> candidatesToUpdate = new List<Lead>();
        candidatesToUpdate.addAll(sourceUpdatesById.values());
        candidatesToUpdate.addAll(targetUpdatesById.values());
        if (!candidatesToUpdate.isEmpty()) {
            update candidatesToUpdate;
        }

        if (!targetCandidateIds.isEmpty()) {
            CandidateHighestLevelUpdater.updationOfHighestLevelOnCandidate(targetCandidateIds);
        }
    }

    private static void validateInputs(Id sourceCandidateId, Id targetCandidateId) {
        if (sourceCandidateId == null || targetCandidateId == null) {
            throw new AuraHandledException('Source and target candidate Ids are required.');
        }
        if (sourceCandidateId == targetCandidateId) {
            throw new AuraHandledException('Source and target candidates cannot be the same.');
        }
    }

    private static Lead buildTargetCandidateUpdate(
        Lead sourceCandidate,
        Lead targetCandidate,
        Lead existingTargetUpdate,
        String sourcePhone,
        String sourceEmail,
        String mergeComments
    ) {
        Lead targetUpdate = existingTargetUpdate == null
            ? new Lead(Id = targetCandidate.Id)
            : existingTargetUpdate;
        Boolean hasChanges = false;
        String resolvedSourcePhone = String.isNotBlank(sourceCandidate.Phone) ? sourceCandidate.Phone : sourcePhone;
        String resolvedSourceEmail = String.isNotBlank(sourceCandidate.Email) ? sourceCandidate.Email : sourceEmail;

        String effectivePhone = String.isNotBlank((String) targetUpdate.get('Phone'))
            ? (String) targetUpdate.get('Phone')
            : targetCandidate.Phone;
        if (String.isBlank(effectivePhone) && String.isNotBlank(resolvedSourcePhone)) {
            targetUpdate.Phone = resolvedSourcePhone;
            hasChanges = true;
        }

        String effectiveMobilePhone = String.isNotBlank((String) targetUpdate.get('MobilePhone'))
            ? (String) targetUpdate.get('MobilePhone')
            : targetCandidate.MobilePhone;
        if (String.isBlank(effectiveMobilePhone) && String.isNotBlank(sourceCandidate.MobilePhone)) {
            targetUpdate.MobilePhone = sourceCandidate.MobilePhone;
            hasChanges = true;
        }

        String effectiveEmail = String.isNotBlank((String) targetUpdate.get('Email'))
            ? (String) targetUpdate.get('Email')
            : targetCandidate.Email;
        if (String.isBlank(effectiveEmail) && String.isNotBlank(resolvedSourceEmail)) {
            targetUpdate.Email = resolvedSourceEmail;
            hasChanges = true;
        }
        if (String.isNotBlank(mergeComments)) {
            targetUpdate.Merge_Comments__c = mergeComments;
            hasChanges = true;
        }

        return hasChanges ? targetUpdate : null;
    }

    private static void reparentRelatedRecords(Map<Id, Id> sourceToTargetCandidateId) {
        if (sourceToTargetCandidateId == null || sourceToTargetCandidateId.isEmpty()) {
            return;
        }

        Set<Id> sourceCandidateIds = sourceToTargetCandidateId.keySet();
        for (String objectApiName : RELATED_OBJECT_API_NAMES) {
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjectType == null) {
                continue;
            }

            Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
            if (!fieldMap.containsKey('Candidate__c')) {
                continue;
            }

            String soql = 'SELECT Id, Candidate__c FROM ' + objectApiName + ' WHERE Candidate__c IN :sourceCandidateIds';
            List<SObject> recordsToUpdate = Database.query(soql);
            if (recordsToUpdate.isEmpty()) {
                continue;
            }

            for (SObject record : recordsToUpdate) {
                Id targetCandidateId = sourceToTargetCandidateId.get((Id) record.get('Candidate__c'));
                if (targetCandidateId != null) {
                    record.put('Candidate__c', targetCandidateId);
                }
            }

            update recordsToUpdate;
        }
    }

    private static Map<Id, String> getSourcePhoneByCandidateId(Set<Id> sourceCandidateIds) {
        Map<Id, String> phoneByCandidateId = new Map<Id, String>();
        if (sourceCandidateIds == null || sourceCandidateIds.isEmpty()) {
            return phoneByCandidateId;
        }

        for (Phone_Number__c phoneRecord : [
            SELECT Candidate__c, Phone__c, Is_Primary__c
            FROM Phone_Number__c
            WHERE Candidate__c IN :sourceCandidateIds
            AND Phone__c != null
            ORDER BY Candidate__c, Is_Primary__c DESC, CreatedDate ASC
        ]) {
            if (!phoneByCandidateId.containsKey(phoneRecord.Candidate__c)) {
                phoneByCandidateId.put(phoneRecord.Candidate__c, phoneRecord.Phone__c);
            }
        }
        return phoneByCandidateId;
    }

    private static Map<Id, String> getSourceEmailByCandidateId(Set<Id> sourceCandidateIds) {
        Map<Id, String> emailByCandidateId = new Map<Id, String>();
        if (sourceCandidateIds == null || sourceCandidateIds.isEmpty()) {
            return emailByCandidateId;
        }

        for (Email__c emailRecord : [
            SELECT Candidate__c, Email__c, Is_Primary__c
            FROM Email__c
            WHERE Candidate__c IN :sourceCandidateIds
            AND Email__c != null
            ORDER BY Candidate__c, Is_Primary__c DESC, CreatedDate ASC
        ]) {
            if (!emailByCandidateId.containsKey(emailRecord.Candidate__c)) {
                emailByCandidateId.put(emailRecord.Candidate__c, emailRecord.Email__c);
            }
        }
        return emailByCandidateId;
    }
}