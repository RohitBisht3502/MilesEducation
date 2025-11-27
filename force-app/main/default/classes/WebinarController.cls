/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public class WebinarController {

    @AuraEnabled(cacheable=true)
    public static List<WebinarDTO> getWebinarsByNameOnly() {
        List<WebinarDTO> out = new List<WebinarDTO>();
        for (Webinar__c w : [SELECT Id, Name,Webinar_Id__c FROM Webinar__c WHERE IsActive__c = TRUE ORDER BY Name ASC LIMIT 200 ]) {
            WebinarDTO d = new WebinarDTO();
            d.id        = w.Id;
            d.name      = w.Name;
            d.webinarId = w.Webinar_Id__c;
            out.add(d);
        }
        return out;
    }

    @AuraEnabled
    public static Id createWebinarMember(Id leadId, Id webinarId) {
        if (leadId == null || webinarId == null) {
            throw new AuraHandledException('Lead and Webinar are required.');
        }

        List<Webinar_Member__c> wmList = [Select id,Lead__c,Webinar__c from Webinar_Member__c where Lead__c = :leadId and Webinar__c = :webinarId limit 1];
        if (!wmList.isEmpty()) {
            throw new AuraHandledException('This lead is already registered for this webinar.');
        }
        
        return System.enqueueJob(new LeadZoomRegistrationJob(leadId, webinarId));
    }

    public class WebinarDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String webinarId;
    }
    
    private static final Integer MAX_QUERY_LIMIT = 2000;
    private static final String ERROR_PREFIX = 'WebinarController Error: ';

    // -------------------------------------------------------------
    // MAIN METHOD → GET ACTIVE WEBINAR ATTENDEES FOR CURRENT USER
    // -------------------------------------------------------------
    @AuraEnabled(cacheable=true)
    public static List<WebinarAttendeeDTO> getActiveWebinarAttendees() {
        try {
            validateUserAccess();
            List<Webinar_Member__c> members = queryActiveWebinarMembers(UserInfo.getUserId());
            return transformToDTO(members);

        } catch (Exception e) {
            logError('getActiveWebinarAttendees failed', e);
            throw new AuraHandledException(ERROR_PREFIX + e.getMessage());
        }
    }

    // -------------------------------------------------------------
    // AUTHORIZED VERSION → GET FOR A SPECIFIC USER (SPOC / GM)
    // -------------------------------------------------------------
    @AuraEnabled
    public static List<WebinarAttendeeDTO> getActiveWebinarAttendeesForUser(Id userId) {
        if (userId == null) {
            throw new AuraHandledException('Invalid userId');
        }
        if (UserInfo.getUserId() != userId && !isCurrentUserGMorAdmin()) {
            throw new AuraHandledException('Insufficient access to view this user data.');
        }

        try {
            List<Webinar_Member__c> members = queryActiveWebinarMembers(userId);
            return transformToDTO(members);

        } catch (Exception e) {
            logError('getActiveWebinarAttendeesForUser failed', e);
            throw new AuraHandledException(ERROR_PREFIX + e.getMessage());
        }
    }

    // -------------------------------------------------------------
    // QUERY: GET ACTIVE WEBINAR MEMBERS LINKED TO USER'S LEADS
    // -------------------------------------------------------------
    private static List<Webinar_Member__c> queryActiveWebinarMembers(Id ownerId) {
        return [
            SELECT 
                Id,
                Status__c,
                Lead__c,
                Lead__r.Name,
                Lead__r.Email__c,
                Lead__r.Phone__c,
                Lead__r.OwnerId,
                Webinar__c,
                Webinar__r.Name,
                Webinar__r.Webinar_Id__c,
                Webinar__r.IsActive__c,
                CreatedDate
            FROM Webinar_Member__c
            WHERE Lead__r.OwnerId = :ownerId
            AND Webinar__r.IsActive__c = TRUE
            LIMIT :MAX_QUERY_LIMIT
        ];
    }

    // -------------------------------------------------------------
    // ACCESS VALIDATION
    // -------------------------------------------------------------
    private static void validateUserAccess() {
        if (!Schema.sObjectType.Webinar_Member__c.isAccessible() ||
            !Schema.sObjectType.Webinar__c.isAccessible() ||
            !Schema.sObjectType.Lead__c.isAccessible()) 
        {
            throw new AuraHandledException('Insufficient permissions to access webinar data.');
        }
    }

    // -------------------------------------------------------------
    // TRANSFORM → DTO
    // -------------------------------------------------------------
    private static List<WebinarAttendeeDTO> transformToDTO(List<Webinar_Member__c> members) {
        List<WebinarAttendeeDTO> dtoList = new List<WebinarAttendeeDTO>();

        for (Webinar_Member__c m : members) {
            dtoList.add(new WebinarAttendeeDTO(m));
        }
        return dtoList;
    }

    // -------------------------------------------------------------
    // HELPER → ROLE / PROFILE VALIDATION
    // -------------------------------------------------------------
    private static Boolean isCurrentUserGMorAdmin() {
        try {
            User u = [SELECT Profile.Name, UserRole.Name FROM User WHERE Id = :UserInfo.getUserId()];
            String roleName = u.UserRole?.Name;
            String profileName = u.Profile?.Name;

            if (roleName != null && roleName.containsIgnoreCase('General Manager')) return true;
            if (profileName != null && profileName.containsIgnoreCase('System Administrator')) return true;

        } catch (Exception e) {
            System.debug('Role check failed: ' + e.getMessage());
        }
        return false;
    }

    // -------------------------------------------------------------
    // ERROR LOGGER
    // -------------------------------------------------------------
    private static void logError(String context, Exception e) {
        System.debug(LoggingLevel.ERROR, context + ' → ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, e.getStackTraceString());
    }

    // -------------------------------------------------------------
    // DTO → CLEAN DATA FOR LWC
    // -------------------------------------------------------------
    public class WebinarAttendeeDTO {
        @AuraEnabled public Id webinarMemberId { get; private set; }
        @AuraEnabled public String webinarId { get; private set; }
        @AuraEnabled public String webinarName { get; private set; }
        @AuraEnabled public Boolean isActive { get; private set; }

        @AuraEnabled public Id leadId { get; private set; }
        @AuraEnabled public String leadName { get; private set; }
        @AuraEnabled public String email { get; private set; }
        @AuraEnabled public String phone { get; private set; }

        @AuraEnabled public String status { get; private set; }
        @AuraEnabled public DateTime createdDate { get; private set; }

        public WebinarAttendeeDTO(Webinar_Member__c m) {
            this.webinarMemberId = m.Id;

            this.webinarId = m.Webinar__r.Webinar_Id__c;
            this.webinarName = m.Webinar__r.Name;
            this.isActive = m.Webinar__r.IsActive__c;

            this.leadId = m.Lead__c;
            this.leadName = m.Lead__r.Name;
            this.email = m.Lead__r.Email__c;
            this.phone = m.Lead__r.Phone__c;

            this.status = m.Status__c;
            this.createdDate = m.CreatedDate;
        }
    }
}