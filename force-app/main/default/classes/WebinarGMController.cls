public with sharing class WebinarGMController {

    private static final Integer MAX_QUERY_LIMIT = 2000;

    // -----------------------------
    // WRAPPER CLASS FOR GM DASHBOARD
    // -----------------------------
    public class SPOCWrapper {
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public Integer totalRegistrations;
        @AuraEnabled public Integer attendedCount;
        @AuraEnabled public Decimal attendanceRate;
        @AuraEnabled public Datetime lastRegistrationDate;
        @AuraEnabled public String avatarUrl;

        public SPOCWrapper(Id uId, String uName) {
            this.userId = uId;
            this.userName = uName;
            this.totalRegistrations = 0;
            this.attendedCount = 0;
            this.attendanceRate = 0;
            this.lastRegistrationDate = null;
            this.avatarUrl = '';
        }
    }

    /**
     * GM Access:
     * - A GM is the Manager of SPOCs → User where another User.ManagerId = GM's Id
     * - GM sees stats of users under them
     * 
     * @return List<SPOCWrapper>
     */
    @AuraEnabled(cacheable=true)
    public static List<SPOCWrapper> getSPOCStats() {

        // Step 1: Identify GM
        Id gmId = UserInfo.getUserId();

        // Step 2: Fetch SPOCs under this GM (manager → SPOC relationship)
        List<User> spocs = [
            SELECT Id, Name
            FROM User
            WHERE ManagerId = :gmId
        ];

        if (spocs.isEmpty()) {
            return new List<SPOCWrapper>();
        }

        // Collect userIds
        Set<Id> spocUserIds = new Set<Id>();
        for (User u : spocs) spocUserIds.add(u.Id);

        // Step 3: Fetch Webinar Member Records of leads owned by these SPOCs
        List<Webinar_Member__c> members = [
            SELECT 
                Id,
                Status__c,
                CreatedDate,
                Lead__r.OwnerId,
                Lead__r.Owner.Name,
                Webinar__r.IsActive__c
            FROM Webinar_Member__c
            WHERE Lead__r.OwnerId IN :spocUserIds
            AND Webinar__r.IsActive__c = TRUE
            ORDER BY CreatedDate DESC
            LIMIT :MAX_QUERY_LIMIT
        ];

        // Step 4: Aggregate into map
        Map<Id, SPOCWrapper> mapSPOC = new Map<Id, SPOCWrapper>();

        for (Webinar_Member__c m : members) {
            Id ownerId = m.Lead__r.OwnerId;
            String ownerName = m.Lead__r.Owner.Name;

            if (!mapSPOC.containsKey(ownerId)) {
                mapSPOC.put(ownerId, new SPOCWrapper(ownerId, ownerName));
            }

            SPOCWrapper sp = mapSPOC.get(ownerId);

            // Total registrations
            sp.totalRegistrations++;

            // Attended
            if (m.Status__c == 'Present') {
                sp.attendedCount++;
            }

            // Last registration date
            if (sp.lastRegistrationDate == null || m.CreatedDate > sp.lastRegistrationDate) {
                sp.lastRegistrationDate = m.CreatedDate;
            }
        }

        // Step 5: Compute attendance rate
        for (SPOCWrapper sw : mapSPOC.values()) {
            if (sw.totalRegistrations > 0) {
                sw.attendanceRate = 
                    (Decimal.valueOf(sw.attendedCount) / Decimal.valueOf(sw.totalRegistrations)) * 100;
                sw.attendanceRate = sw.attendanceRate.setScale(1);
            } else {
                sw.attendanceRate = 0;
            }
        }

        // Step 6: Sort by total registrations (desc)
        List<SPOCWrapper> result = new List<SPOCWrapper>(mapSPOC.values());
        result.sort(new SPOCSortByRegistrations());

        return result;
    }

    // -----------------------------
    // SORTING LOGIC
    // -----------------------------
    public class SPOCSortByRegistrations implements Comparator<SPOCWrapper> {
        public Integer compare(SPOCWrapper a, SPOCWrapper b) {
            Integer aVal = a.totalRegistrations == null ? 0 : a.totalRegistrations;
            Integer bVal = b.totalRegistrations == null ? 0 : b.totalRegistrations;

            if (aVal == bVal) return 0;
            return (aVal > bVal) ? -1 : 1; // descending
        }
    }
}