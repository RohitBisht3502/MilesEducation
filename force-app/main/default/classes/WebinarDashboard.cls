public with sharing class WebinarDashboard {

    private static final Integer MAX_QUERY_LIMIT = 2000;

    @AuraEnabled(cacheable=true)
    public static List<WebinarMemberDTO> getMembersByWebinar(Id webinarId) {
        if (webinarId == null) {
            return new List<WebinarMemberDTO>();
        }

        validateUserAccess();
        Id currentUserId = UserInfo.getUserId();
        List<User> directReports = [
            SELECT Id
            FROM User
            WHERE ManagerId = :currentUserId
            AND IsActive = true
            LIMIT :MAX_QUERY_LIMIT
        ];

        List<Webinar_Member__c> members;
        if (isCurrentUserSystemAdmin()) {
            members = queryMembersByWebinar(webinarId);
        } else if (!directReports.isEmpty()) {
            Set<Id> spocIds = new Set<Id>();
            for (User userRec : directReports) {
                spocIds.add(userRec.Id);
            }
            members = queryMembersByWebinarAndOwners(webinarId, spocIds);
        } else {
            members = queryMembersByWebinarAndOwner(webinarId, currentUserId);
        }

        List<WebinarMemberDTO> out = new List<WebinarMemberDTO>();
        for (Webinar_Member__c m : members) {
            out.add(new WebinarMemberDTO(m));
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<SpocWrapper> getSpocOptions(Id webinarId) {
        try {
            Set<Id> ownerIds = new Set<Id>();
            List<SpocWrapper> spocOptions = new List<SpocWrapper>();
            Boolean isSystemAdmin = isCurrentUserSystemAdmin();
            Id currentUserId = UserInfo.getUserId();

            List<Webinar_Member__c> members = [
                SELECT Id, OwnerId, Owner.Name
                FROM Webinar_Member__c
                WHERE Webinar__c = :webinarId
                AND OwnerId != null
            ];

            for (Webinar_Member__c member : members) {
                if (member.OwnerId != null) {
                    ownerIds.add(member.OwnerId);
                }
            }

            if (!ownerIds.isEmpty()) {
                List<User> ownerUsers;
                if (isSystemAdmin) {
                    ownerUsers = [
                        SELECT Id, Name, IsActive, ManagerId, Manager.Name, Manager.Profile.Name
                        FROM User
                        WHERE Id IN :ownerIds
                        AND IsActive = true
                        ORDER BY Manager.Name, Name
                    ];
                } else {
                    ownerUsers = [
                        SELECT Id, Name, IsActive, ManagerId, Manager.Name, Manager.Profile.Name
                        FROM User
                        WHERE Id IN :ownerIds
                        AND ManagerId = :currentUserId
                        AND IsActive = true
                        ORDER BY Name
                    ];
                }

                for (User owner : ownerUsers) {
                    if (isSystemAdmin && !isGMProfileName(owner.Manager != null ? owner.Manager.Profile.Name : null)) {
                        continue;
                    }

                    spocOptions.add(new SpocWrapper(owner.Id, owner.Name, owner.ManagerId, owner.Manager.Name));
                }
            }

            return spocOptions;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching SPOC options: ' + e.getMessage());
        }
    }

    private static List<Webinar_Member__c> queryMembersByWebinar(Id webinarId) {
        return [
            SELECT
                Id,
                Attendance_Status__c,
                Duration__c,
                CreatedDate,
                Lead__c,
                Lead__r.Name,
                Lead__r.Email__c,
                Lead__r.Phone__c,
                Lead__r.OwnerId,
                Lead__r.Owner.Name,
                Webinar__c,
                Webinar__r.Name,
                Webinar__r.Webinar_Id__c
            FROM Webinar_Member__c
            WHERE Webinar__c = :webinarId
            ORDER BY CreatedDate DESC
            LIMIT :MAX_QUERY_LIMIT
        ];
    }

    private static List<Webinar_Member__c> queryMembersByWebinarAndOwner(Id webinarId, Id ownerId) {
        return [
            SELECT
                Id,
                Attendance_Status__c,
                Duration__c,
                CreatedDate,
                Lead__c,
                Lead__r.Name,
                Lead__r.Email__c,
                Lead__r.Phone__c,
                Lead__r.OwnerId,
                Lead__r.Owner.Name,
                Webinar__c,
                Webinar__r.Name,
                Webinar__r.Webinar_Id__c
            FROM Webinar_Member__c
            WHERE Webinar__c = :webinarId
            AND Lead__r.OwnerId = :ownerId
            ORDER BY CreatedDate DESC
            LIMIT :MAX_QUERY_LIMIT
        ];
    }

    private static List<Webinar_Member__c> queryMembersByWebinarAndOwners(Id webinarId, Set<Id> ownerIds) {
        if (ownerIds.isEmpty()) {
            return new List<Webinar_Member__c>();
        }

        return [
            SELECT
                Id,
                Attendance_Status__c,
                Duration__c,
                CreatedDate,
                Lead__c,
                Lead__r.Name,
                Lead__r.Email__c,
                Lead__r.Phone__c,
                Lead__r.OwnerId,
                Lead__r.Owner.Name,
                Webinar__c,
                Webinar__r.Name,
                Webinar__r.Webinar_Id__c
            FROM Webinar_Member__c
            WHERE Webinar__c = :webinarId
            AND Lead__r.OwnerId IN :ownerIds
            ORDER BY CreatedDate DESC
            LIMIT :MAX_QUERY_LIMIT
        ];
    }

    @AuraEnabled
    public static LiveSyncResultDTO syncLiveWebinarAttendees(String webinarId) {
        try {
            if (String.isBlank(webinarId)) {
                throw new AuraHandledException('Webinar ID is required');
            }

            String responseBody = Callout_WebinarAttendee.getLiveWebinarAttendees(webinarId);
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);

            if (responseMap == null) {
                throw new AuraHandledException('Invalid response from webinar service');
            }

            Set<String> liveAttendeeEmails = new Set<String>();
            List<String> liveEmailsList = new List<String>();
            Map<String, Decimal> durationByEmail = new Map<String, Decimal>();

            if (responseMap.containsKey('registrants') && responseMap.get('registrants') instanceof List<Object>) {
                List<Object> registrants = (List<Object>) responseMap.get('registrants');
                for (Object registrantObj : registrants) {
                    if (!(registrantObj instanceof Map<String, Object>)) {
                        continue;
                    }

                    Map<String, Object> registrant = (Map<String, Object>) registrantObj;
                    String email = (String) registrant.get('participant_email');
                    email = String.isBlank(email) ? null : email.toLowerCase().trim();

                    if (String.isNotBlank(email)) {
                        liveAttendeeEmails.add(email);
                        liveEmailsList.add(email);
                        Decimal duration = parseDecimal(registrant.get('live_duration'));
                        if (duration == null) {
                            duration = parseDecimal(registrant.get('duration'));
                        }
                        if (duration == null) {
                            duration = parseDecimal(registrant.get('participant_duration'));
                        }
                        if (duration != null) {
                            durationByEmail.put(email, duration);
                        }
                    }
                }
            } else if (responseMap.containsKey('attendees') && responseMap.get('attendees') instanceof List<Object>) {
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

            List<Webinar_Member__c> membersToUpdate = new List<Webinar_Member__c>();
            if (!durationByEmail.isEmpty()) {
                for (Webinar_Member__c wm : [
                    SELECT Id, Duration__c, Lead__r.Email__c
                    FROM Webinar_Member__c
                    WHERE Webinar__r.Webinar_Id__c = :webinarId
                    AND Lead__r.Email__c IN :durationByEmail.keySet()
                ]) {
                    String email = wm.Lead__r != null && String.isNotBlank(wm.Lead__r.Email__c)
                        ? wm.Lead__r.Email__c.toLowerCase().trim()
                        : null;
                    Decimal duration = email != null ? durationByEmail.get(email) : null;
                    if (duration != null && wm.Duration__c != duration) {
                        wm.Duration__c = duration;
                        membersToUpdate.add(wm);
                    }
                }
            }

            if (!membersToUpdate.isEmpty()) {
                update membersToUpdate;
            }

            return new LiveSyncResultDTO(membersToUpdate.size(), liveAttendeeEmails.size(), liveEmailsList, durationByEmail);
        } catch (Exception e) {
            throw new AuraHandledException('Error syncing live webinar attendees: ' + e.getMessage());
        }
    }

    private static Decimal parseDecimal(Object value) {
        if (value == null) return null;
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    private static void validateUserAccess() {
        if (!Schema.sObjectType.Webinar_Member__c.isAccessible() ||
            !Schema.sObjectType.Webinar__c.isAccessible() ||
            !Schema.sObjectType.Lead__c.isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to access webinar data.');
        }
    }

    private static Boolean isCurrentUserSystemAdmin() {
        try {
            User currentUser = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            return currentUser.Profile != null &&
                currentUser.Profile.Name != null &&
                currentUser.Profile.Name.containsIgnoreCase('System Administrator');
        } catch (Exception e) {
            return false;
        }
    }

    private static Boolean isGMProfileName(String profileName) {
        return String.isNotBlank(profileName) &&
            (profileName.containsIgnoreCase('GM') || profileName.containsIgnoreCase('General Manager'));
    }

    public class WebinarMemberDTO {
        @AuraEnabled public Id webinarMemberId { get; private set; }
        @AuraEnabled public String webinarId { get; private set; }
        @AuraEnabled public String webinarName { get; private set; }

        @AuraEnabled public Id leadId { get; private set; }
        @AuraEnabled public String leadName { get; private set; }
        @AuraEnabled public String email { get; private set; }
        @AuraEnabled public String phone { get; private set; }

        @AuraEnabled public String status { get; private set; }
        @AuraEnabled public Decimal duration { get; private set; }
        @AuraEnabled public DateTime createdDate { get; private set; }

        @AuraEnabled public String spocName { get; private set; }
        @AuraEnabled public Id spocId { get; private set; }

        public WebinarMemberDTO(Webinar_Member__c m) {
            this.webinarMemberId = m.Id;
            this.webinarId = m.Webinar__r.Webinar_Id__c;
            this.webinarName = m.Webinar__r.Name;
            this.leadId = m.Lead__c;
            this.leadName = m.Lead__r.Name;
            this.email = m.Lead__r.Email__c;
            this.phone = m.Lead__r.Phone__c;
            this.status = m.Attendance_Status__c;
            this.duration = m.Duration__c;
            this.createdDate = m.CreatedDate;
            this.spocName = m.Lead__r.Owner.Name;
            this.spocId = m.Lead__r.OwnerId;
        }
    }

    public class SpocWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String managerId { get; set; }
        @AuraEnabled public String managerName { get; set; }

        public SpocWrapper(String id, String name) {
            this.id = id;
            this.name = name;
        }

        public SpocWrapper(String id, String name, String managerId, String managerName) {
            this.id = id;
            this.name = name;
            this.managerId = managerId;
            this.managerName = managerName;
        }
    }

    public class LiveSyncResultDTO {
        @AuraEnabled public Integer updatedCount { get; private set; }
        @AuraEnabled public Integer liveAttendeesCount { get; private set; }
        @AuraEnabled public List<String> liveEmails { get; private set; }
        @AuraEnabled public Map<String, Decimal> durationByEmail { get; private set; }

        public LiveSyncResultDTO(Integer updated, Integer liveCount, List<String> emails, Map<String, Decimal> durationByEmail) {
            this.updatedCount = updated;
            this.liveAttendeesCount = liveCount;
            this.liveEmails = emails;
            this.durationByEmail = durationByEmail;
        }
    }
}