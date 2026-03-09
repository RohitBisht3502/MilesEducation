public with sharing class WebinarDashboard {

    private static final Integer MAX_QUERY_LIMIT = 2000;

    @AuraEnabled(cacheable=true)
    public static List<WebinarMemberDTO> getMembersByWebinar(Id webinarId) {
        if (webinarId == null) {
            return new List<WebinarMemberDTO>();
        }

        validateUserAccess();

        List<Webinar_Member__c> members = [
            SELECT
                Id,
                Attendance_Status__c,
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

    private static void validateUserAccess() {
        if (!Schema.sObjectType.Webinar_Member__c.isAccessible() ||
            !Schema.sObjectType.Webinar__c.isAccessible() ||
            !Schema.sObjectType.Lead__c.isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to access webinar data.');
        }
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
            this.createdDate = m.CreatedDate;
            this.spocName = m.Lead__r.Owner.Name;
            this.spocId = m.Lead__r.OwnerId;
        }
    }

    public class SpocWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }

        public SpocWrapper(String id, String name) {
            this.id = id;
            this.name = name;
        }
    }
}