// file: RunoCallIdentityService.cls
public without sharing class RunoCallIdentityService {

    public class IdentityDTO {
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String city;
        @AuraEnabled public String source;
        @AuraEnabled public String stage;
        @AuraEnabled public String canId;
 @AuraEnabled public Datetime createdDate;
    @AuraEnabled public String highestLevel;
    @AuraEnabled public String mhpTag;
    @AuraEnabled public String leadOwner;
    @AuraEnabled public Id candidateId;

    }

    public class RelatedLeadDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String course;
        @AuraEnabled public String stage;
    }

    public class LeadStageUpdate {
        @AuraEnabled public Id id;
        @AuraEnabled public String stage;
    }

    @AuraEnabled(cacheable=true)
    public static IdentityDTO getIdentity(Id recordId) {
        System.debug('RunoCallIdentityService.getIdentity recordId >>> ' + recordId);
        if (recordId == null) return null;

        SObjectType sObjType = recordId.getSObjectType();

        /* ===================== LEAD ===================== */
        if (sObjType == Lead__c.SObjectType) {
            Lead__c l = [
                SELECT Id, Name, Email__c, Phone__c, City__c, Course__c, Stage__c, CAN_ID__c, Candidate__c,
                CreatedDate,
   
       Is_ReEnquiry__c,
       Owner.Name
                FROM Lead__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            IdentityDTO dto = new IdentityDTO();
            dto.name   = l.Name;
            dto.email  = l.Email__c;
            dto.phone  = l.Phone__c;
            dto.city   = l.City__c;
            dto.source = l.Course__c;
            dto.stage  = l.Stage__c;
    dto.canId  = l.CAN_ID__c;
    dto.candidateId = l.Candidate__c;
               dto.createdDate  = l.CreatedDate;
    // dto.highestLevel = l.Highest_Level__c;

    
    dto.mhpTag = l.Is_ReEnquiry__c ? 'Yes' : 'No';

    dto.leadOwner = l.Owner.Name;

    return dto;

           
        }

        /* ===================== CALL LOG ===================== */
        if (sObjType == Call_Log__c.SObjectType) {
            Call_Log__c cl = [
                SELECT Id, Customer_Name__c, Phone_Number__c, Candidate__c
                FROM Call_Log__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            IdentityDTO dto = new IdentityDTO();
            dto.name   = cl.Customer_Name__c;
            dto.email  = 'NA';
            dto.phone  = cl.Phone_Number__c;
            dto.city   = 'NA';
            dto.source = 'NA';
            dto.stage  = 'NA';
            dto.canId  = null;
            dto.candidateId = cl.Candidate__c;

            return dto;
        }

        return null;
    }

    @AuraEnabled(cacheable=true)
    public static List<RelatedLeadDTO> getRelatedLeads(Id candidateId) {
        if (candidateId == null) return new List<RelatedLeadDTO>();

        List<Lead__c> leads = [
            SELECT Id, Course__c, Stage__c
            FROM Lead__c
            WHERE Candidate__c = :candidateId
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];

        List<RelatedLeadDTO> res = new List<RelatedLeadDTO>();
        for (Lead__c l : leads) {
            RelatedLeadDTO dto = new RelatedLeadDTO();
            dto.id = l.Id;
            dto.course = l.Course__c;
            dto.stage = l.Stage__c;
            res.add(dto);
        }

        return res;
    }

    @AuraEnabled
    public static void updateRelatedLeadStages(List<LeadStageUpdate> updates) {
        if (updates == null || updates.isEmpty()) return;

        List<Lead__c> toUpdate = new List<Lead__c>();
        for (LeadStageUpdate u : updates) {
            if (u == null || u.id == null) continue;
            Lead__c l = new Lead__c(Id = u.id);
            l.Stage__c = String.isBlank(u.stage) ? null : u.stage;
            toUpdate.add(l);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }


    

 @AuraEnabled
public static Id createRelatedLead(Id candidateId, String course, Id sourceRecordId) {

    if (candidateId == null) {
        throw new AuraHandledException('Candidate Id is required.');
    }
    if (String.isBlank(course)) {
        throw new AuraHandledException('Course is required.');
    }

    // Prevent duplicate course lead
    List<Lead__c> existing = [
        SELECT Id
        FROM Lead__c
        WHERE Candidate__c = :candidateId
        AND Course__c = :course
        LIMIT 1
    ];
    if (!existing.isEmpty()) {
        throw new AuraHandledException('Lead already exists for this course.');
    }

    // ✅ Candidate = Standard Lead
    Lead candidate = [
        SELECT Id, Email
        FROM Lead
        WHERE Id = :candidateId
        LIMIT 1
    ];

    Lead__c sourceLead;

    if (sourceRecordId != null && sourceRecordId.getSObjectType() == Lead__c.SObjectType) {
        sourceLead = [
            SELECT Id, Name, Phone__c, Email__c
            FROM Lead__c
            WHERE Id = :sourceRecordId
            LIMIT 1
        ];
    } else {
        List<Lead__c> leads = [
            SELECT Id, Name, Phone__c, Email__c
            FROM Lead__c
            WHERE Candidate__c = :candidateId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!leads.isEmpty()) {
            sourceLead = leads[0];
        }
    }

    Lead__c newLead = new Lead__c();
    newLead.Candidate__c = candidateId;
    newLead.Course__c = course;

    // ✅ Email from Standard Lead
    if (!String.isBlank(candidate.Email)) {
        newLead.Email__c = candidate.Email;
    }
    else if (sourceLead != null && !String.isBlank(sourceLead.Email__c)) {
        newLead.Email__c = sourceLead.Email__c;
    }
    else {
        throw new AuraHandledException('Candidate does not have an email.');
    }

    if (sourceLead != null) {
        newLead.Name = sourceLead.Name;
        newLead.Phone__c = sourceLead.Phone__c;
    } else {
        newLead.Name = 'New Lead';
    }

    List<RecordType> rts = [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Lead__c'
        AND Name = :course
        AND IsActive = true
        LIMIT 1
    ];
    if (!rts.isEmpty()) {
        newLead.RecordTypeId = rts[0].Id;
    }

    insert newLead;
    return newLead.Id;
}
    /* Optional wrapper for LWC clarity */
    @AuraEnabled(cacheable=true)
    public static IdentityDTO getCourseIdentity(Id recordId) {
        return getIdentity(recordId);
    }
}