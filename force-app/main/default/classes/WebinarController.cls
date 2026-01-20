/*
    Author       : ROHIT SINGH BISHT / Dheeraj Kumar
    Description  : Controller for Webinar Management with Live Attendee Sync
    Fixed Issues : Webinar filtering & GM live sync metrics
*/
public class WebinarController {

    @AuraEnabled(cacheable=true)
    public static List<WebinarDTO> getWebinarsByNameOnly() {
        List<WebinarDTO> out = new List<WebinarDTO>();
        Datetime nowDt = System.now();
        for (Webinar__c w : [SELECT Id, Name,Webinar_Id__c FROM Webinar__c WHERE IsActive__c = TRUE  ORDER BY Name ASC LIMIT 200 ]) {
            WebinarDTO d = new WebinarDTO();
            d.id        = w.Id;
            d.name      = w.Name;
            d.webinarId = w.Webinar_Id__c;
            out.add(d);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<WebinarDTO> getWebinarsByNameOrId(String searchKey) {
        // if (String.isBlank(searchKey)) {
        //     return getWebinarsByNameOnly();
        // }

        String key = '%' + String.escapeSingleQuotes(searchKey.trim()) + '%';
        List<WebinarDTO> out = new List<WebinarDTO>();

        for (Webinar__c w : [
            SELECT Id, Name, Webinar_Id__c
            FROM Webinar__c
            WHERE IsActive__c = TRUE
            AND (Name LIKE :key OR Webinar_Id__c LIKE :key)
            AND Status__c = 'Created'
            ORDER BY Name ASC
            LIMIT 200
        ]) {
            WebinarDTO d = new WebinarDTO();
            d.id = w.Id;
            d.name = w.Name;
            d.webinarId = w.Webinar_Id__c;
            out.add(d);
        }
        System.debug('Webinar search results for key "' + searchKey + '": ' + out);
        return out;
    }

    @AuraEnabled
    public static Id createWebinarMember(Id recordId, Id webinarId) {
        if (recordId == null || webinarId == null) {
            throw new AuraHandledException('Record and Webinar are required.');
        }

        List<Webinar_Member__c> wmList = [SELECT Id, Lead__c, Enquiry__c, Webinar__c FROM Webinar_Member__c WHERE Webinar__c = :webinarId AND (Lead__c = :recordId OR Enquiry__c = :recordId) LIMIT 1];
        if (!wmList.isEmpty()) {
            throw new AuraHandledException('This record is already registered for this webinar.');
        }

        return System.enqueueJob(new LeadZoomRegistrationJob(recordId, webinarId));
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
    // MODIFIED: Added optional webinarId parameter
    // -------------------------------------------------------------
    @AuraEnabled(cacheable=true)
    public static List<WebinarAttendeeDTO> getActiveWebinarAttendees(String webinarId) {
        try {
            validateUserAccess();
            List<Webinar_Member__c> members;
            
            if (String.isNotBlank(webinarId)) {
                members = queryActiveWebinarMembers(UserInfo.getUserId(), webinarId);
            } else {
                members = queryActiveWebinarMembers(UserInfo.getUserId());
            }
            
            return transformToDTO(members);

        } catch (Exception e) {
            logError('getActiveWebinarAttendees failed', e);
            throw new AuraHandledException(ERROR_PREFIX + e.getMessage());
        }
    }

    // -------------------------------------------------------------
    // GET MANAGED USERS FOR GM
    // -------------------------------------------------------------
    @AuraEnabled(cacheable=true)
    public static List<User> getManagedUsers() {
        try {
            Id currentUserId = UserInfo.getUserId();
            
            return [
                SELECT Id, Name, Email, Phone, Title, IsActive
                FROM User 
                WHERE ManagerId = :currentUserId 
                AND IsActive = true
                ORDER BY Name
                LIMIT :MAX_QUERY_LIMIT
            ];
        } catch (Exception e) {
            logError('getManagedUsers failed', e);
            throw new AuraHandledException(ERROR_PREFIX + e.getMessage());
        }
    }

    // -------------------------------------------------------------
    // AUTHORIZED VERSION → GET FOR A SPECIFIC USER (SPOC / GM)
    // MODIFIED: Added optional webinarId parameter
    // -------------------------------------------------------------
    @AuraEnabled
    public static List<WebinarAttendeeDTO> getActiveWebinarAttendeesForUser(Id userId, String webinarId) {
        if (userId == null) {
            throw new AuraHandledException('Invalid userId');
        }
        if (UserInfo.getUserId() != userId && !isCurrentUserGMorAdmin()) {
            throw new AuraHandledException('Insufficient access to view this user data.');
        }

        try {
            List<Webinar_Member__c> members;
            
            if (String.isNotBlank(webinarId)) {
                members = queryActiveWebinarMembers(userId, webinarId);
            } else {
                members = queryActiveWebinarMembers(userId);
            }
            
            return transformToDTO(members);

        } catch (Exception e) {
            logError('getActiveWebinarAttendeesForUser failed', e);
            throw new AuraHandledException(ERROR_PREFIX + e.getMessage());
        }
    }

    // -------------------------------------------------------------
    // GET WEBINAR DATA FOR SPECIFIC SPOC (GM VIEW)
    // -------------------------------------------------------------
    @AuraEnabled(cacheable=true)
    public static List<WebinarAttendeeDTO> getWebinarDataForSpoc(Id spocId) {
        try {
            if (!isCurrentUserGMorAdmin()) {
                throw new AuraHandledException('Insufficient permissions to view SPOC data.');
            }
            
            validateUserAccess();
            List<Webinar_Member__c> members = queryActiveWebinarMembers(spocId);
            return transformToDTO(members);

        } catch (Exception e) {
            logError('getWebinarDataForSpoc failed', e);
            throw new AuraHandledException(ERROR_PREFIX + e.getMessage());
        }
    }

    // -------------------------------------------------------------
    // NEW: SYNC LIVE WEBINAR ATTENDEES - RETURNS EMAIL LIST
    // -------------------------------------------------------------
    @AuraEnabled
    public static LiveSyncResultDTO syncLiveWebinarAttendees(String webinarId) {
        try {
            if (String.isBlank(webinarId)) {
                throw new AuraHandledException('Webinar ID is required');
            }

            // Call the webservice to get live attendees
            String responseBody = Callout_WebinarAttendee.getLiveWebinarAttendees(webinarId);
           
            // Parse JSON response
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            
            if (responseMap == null) {
                throw new AuraHandledException('Invalid response from webinar service');
            }

            Set<String> liveAttendeeEmails = new Set<String>();
            List<String> liveEmailsList = new List<String>();

            // New response format:
            // { "registrants": [ { "participant_email": "...", "registrant_id": "..." }, ... ] }
            if (responseMap.containsKey('registrants') && responseMap.get('registrants') instanceof List<Object>) {
                List<Object> registrants = (List<Object>)responseMap.get('registrants');
                for (Object registrantObj : registrants) {
                    if (!(registrantObj instanceof Map<String, Object>)) continue;
                    Map<String, Object> registrant = (Map<String, Object>)registrantObj;
                    String email = (String)registrant.get('participant_email');
                    email = String.isBlank(email) ? null : email.toLowerCase().trim();
                    if (String.isNotBlank(email)) {
                        liveAttendeeEmails.add(email);
                        liveEmailsList.add(email);
                    }
                }
            }
            // Backward compatible older format:
            // { "attendees": [ "a@b.com", ... ] }
            else if (responseMap.containsKey('attendees') && responseMap.get('attendees') instanceof List<Object>) {
                List<Object> attendeesList = (List<Object>) responseMap.get('attendees');
                for (Object emailObj : attendeesList) {
                    String email = String.valueOf(emailObj).toLowerCase().trim();
                    if (String.isNotBlank(email)) {
                        liveAttendeeEmails.add(email);
                        liveEmailsList.add(email);
                    }
                }
            } else {
                throw new AuraHandledException('Invalid response from webinar service');
            }
            
            return new LiveSyncResultDTO(0, liveAttendeeEmails.size(), liveEmailsList);

        } catch (Exception e) {
            logError('syncLiveWebinarAttendees failed', e);
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
                Attendance_Status__c,
                Lead__c,
                Lead__r.Name,
                Lead__r.Email__c,
                Lead__r.Phone__c,
                Lead__r.OwnerId,
                Lead__r.Owner.Name,
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

    // OVERLOADED METHOD WITH WEBINAR FILTER
    private static List<Webinar_Member__c> queryActiveWebinarMembers(Id ownerId, String webinarId) {
        return [
            SELECT 
                Id, Attendance_Status__c, Lead__c, Lead__r.Name, Lead__r.Email__c, Lead__r.Phone__c, 
                Lead__r.OwnerId, Lead__r.Owner.Name, Webinar__c, Webinar__r.Name, 
                Webinar__r.Webinar_Id__c, Webinar__r.IsActive__c, CreatedDate
            FROM Webinar_Member__c
            WHERE Lead__r.OwnerId = :ownerId
            AND Webinar__r.Webinar_Id__c = :webinarId
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
        
        // SPOC Information
        @AuraEnabled public String spocName { get; private set; }
        @AuraEnabled public Id spocId { get; private set; }

        public WebinarAttendeeDTO(Webinar_Member__c m) {
            this.webinarMemberId = m.Id;

            this.webinarId = m.Webinar__r.Webinar_Id__c;
            this.webinarName = m.Webinar__r.Name;
            this.isActive = m.Webinar__r.IsActive__c;

            this.leadId = m.Lead__c;
            this.leadName = m.Lead__r.Name;
            this.email = m.Lead__r.Email__c;
            this.phone = m.Lead__r.Phone__c;

            this.status = m.Attendance_Status__c;
            this.createdDate = m.CreatedDate;
            
            // SPOC info from Lead Owner
            this.spocName = m.Lead__r.Owner.Name;
            this.spocId = m.Lead__r.OwnerId;
        }
    }

    // -------------------------------------------------------------
    // LIVE SYNC RESULT DTO WITH EMAIL LIST
    // -------------------------------------------------------------
    public class LiveSyncResultDTO {
        @AuraEnabled public Integer updatedCount { get; private set; }
        @AuraEnabled public Integer liveAttendeesCount { get; private set; }
        @AuraEnabled public List<String> liveEmails { get; private set; }

        public LiveSyncResultDTO(Integer updated, Integer liveCount, List<String> emails) {
            this.updatedCount = updated;
            this.liveAttendeesCount = liveCount;
            this.liveEmails = emails;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<SpocWrapper> getSpocOptions(String webinarId) {
        try {
            Set<Id> ownerIds = new Set<Id>();
            List<SpocWrapper> spocOptions = new List<SpocWrapper>();
            
            // Query webinar members to get record owners
            List<Webinar_Member__c> members = [
                SELECT Id, OwnerId, Owner.Name 
                FROM Webinar_Member__c 
                WHERE Webinar__c = :webinarId 
                AND OwnerId != null
            ];
            
            // Collect unique owner IDs
            for (Webinar_Member__c member : members) {
                if (member.OwnerId != null) {
                    ownerIds.add(member.OwnerId);
                }
            }
            
            // Query owner users (SPOCs)
            if (!ownerIds.isEmpty()) {
                List<User> ownerUsers = [
                    SELECT Id, Name, IsActive 
                    FROM User 
                    WHERE Id IN :ownerIds 
                    AND IsActive = true
                    ORDER BY Name
                ];
                
                for (User owner : ownerUsers) {
                    spocOptions.add(new SpocWrapper(owner.Id, owner.Name));
                }
            }
            
            return spocOptions;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching SPOC options: ' + e.getMessage());
        }
    }

    // Wrapper class for SPOC options
    public class SpocWrapper {
        @AuraEnabled
        public String id { get; set; }
        @AuraEnabled
        public String name { get; set; }
        
        public SpocWrapper(String id, String name) {
            this.id = id;
            this.name = name;
        }
    }
}