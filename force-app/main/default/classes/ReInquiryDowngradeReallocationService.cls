/**
 * Author: Rohit Singh Bisht
 * Service: Re-Inquiry + Downgraded Reallocation
 *
 * Runs when Lead becomes eligible:
 *  - Is_ReEnquiry__c = true
 *  - Downgraded__c  = true
 *  - and previously it was NOT eligible (prevents reruns)
 *
 * Candidate Pool Source:
 *  - Round_Robin_Pool__c (NOT User directly)
 *
 * Round_Robin_Pool__c Filters:
 *  - Active__c = true
 *  - Type__c = 'CC - Pre Enrollment'
 *  - Assigned_Weight__c > 0
 *  - City__c = Lead.City__c
 *  - Lead_Source__c = Lead.Source__c   (bucket/source)
 *  - Course_Bucket__c = Lead.Course_Bucket__c
 *  - Sales_Rep__c != null
 *  - Ordered by Sequence__c (ascending) for stable ordering / fallback
 *
 * Rotation Rules:
 *  - MUST NOT assign back to the last assigned SPOC (from Activity Log New_Owner__c)
 *  - If only one SPOC exists, assign back to same (exception)
 *  - Churn: prefers SPOC never assigned; else least-recently assigned
 *
 * Activity Log (Activity_Log__c) is stored at Candidate level:
 *  - Activity_Log__c.Candidate__c is lookup to Candidate
 *  - Lead__c has Candidate__c lookup
 *
 * Activity Log fields:
 *  - Previous_Owner__c + New_Owner__c for audit + rotation history
 *  - Action_Performed_By__c = running user (automation/system)
 */
public without sharing class ReInquiryDowngradeReallocationService {

    // =========================
    // CONFIG
    // =========================
    private static final String RR_TYPE_ROUND_ROBIN = 'CC - Pre Enrollment';
    private static final String LOG_TYPE_OWNER_ASSIGNMENT = 'Lead Downgraded';

    // =========================
    // ENTRY
    // =========================
    public static void handleAfterUpdate(List<Lead__c> newList, Map<Id, Lead__c> oldMap) {
        System.debug(LoggingLevel.INFO,
            'ReInquiryDowngradeReallocationService.handleAfterUpdate :: START, newList=' +
            (newList == null ? 0 : newList.size())
        );

        if (newList == null || newList.isEmpty() || oldMap == null) {
            System.debug(LoggingLevel.WARN,
                'ReInquiryDowngradeReallocationService.handleAfterUpdate :: No data / oldMap missing. Exiting.'
            );
            return;
        }

        List<Lead__c> eligible = new List<Lead__c>();

        for (Lead__c l : newList) {
            Lead__c oldL = oldMap.get(l.Id);

            Boolean nowEligible = (l.Is_ReEnquiry__c == true && l.Downgraded__c == true);
            Boolean wasEligible = (oldL != null && oldL.Is_ReEnquiry__c == true && oldL.Downgraded__c == true);

            // Run only when it becomes eligible in this update (prevents repeated re-assignments)
            if (nowEligible && !wasEligible) {

                // Routing fields (key) must exist
                if (String.isBlank(l.City__c) || String.isBlank(l.Source__c) || String.isBlank(l.Course_Bucket__c)) {
                    System.debug(LoggingLevel.WARN,
                        'ReInquiryDowngradeReallocationService :: Skipping lead due to missing routing fields. ' +
                        'LeadId=' + l.Id +
                        ', City=' + l.City__c +
                        ', Source=' + l.Source__c +
                        ', CourseBucket=' + l.Course_Bucket__c
                    );
                    continue;
                }

                // Candidate must exist to read/write history at candidate level
                if (l.Candidate__c == null) {
                    System.debug(LoggingLevel.WARN,
                        'ReInquiryDowngradeReallocationService :: Skipping lead due to missing Candidate__c. LeadId=' + l.Id
                    );
                    continue;
                }

                eligible.add(l);
            }
        }

        System.debug(LoggingLevel.INFO,
            'ReInquiryDowngradeReallocationService.handleAfterUpdate :: Eligible leads count=' + eligible.size()
        );

        if (eligible.isEmpty()) {
            System.debug(LoggingLevel.INFO,
                'ReInquiryDowngradeReallocationService.handleAfterUpdate :: No eligible leads. END.'
            );
            return;
        }

        processReallocation(eligible);

        System.debug(LoggingLevel.INFO, 'ReInquiryDowngradeReallocationService.handleAfterUpdate :: END');
    }

    // =========================
    // CORE PROCESS
    // =========================
    private static void processReallocation(List<Lead__c> leads) {
        System.debug(LoggingLevel.INFO,
            'ReInquiryDowngradeReallocationService.processReallocation :: START, leads=' + leads.size()
        );

        // Lead -> Candidate mapping for reading candidate-level logs
        Set<Id> candidateIds = new Set<Id>();
        Map<Id, Id> leadToCandidate = new Map<Id, Id>();

        for (Lead__c l : leads) {
            if (l.Candidate__c != null) {
                candidateIds.add(l.Candidate__c);
                leadToCandidate.put(l.Id, l.Candidate__c);
            }
        }

        // 1) Fetch assignment history for these candidates (latest first)
        Map<Id, List<Activity_Log__c>> candidateLogsMap = fetchCandidateAssignmentLogs(candidateIds);

        // 2) Build candidate pool from Round_Robin_Pool__c based on lead routing fields
        Map<String, List<Id>> poolByKey = buildSpocPoolFromRR(leads);

        List<Lead__c> toUpdate = new List<Lead__c>();
        List<Activity_Log__c> logsToInsert = new List<Activity_Log__c>();

        for (Lead__c l : leads) {

            String key = getKey(l.City__c, l.Source__c, l.Course_Bucket__c);
            List<Id> candidates = poolByKey.get(key);

            if (candidates == null || candidates.isEmpty()) {
                System.debug(LoggingLevel.WARN,
                    'ReInquiryDowngradeReallocationService :: No RR pool candidates found. LeadId=' + l.Id +
                    ', key=' + key +
                    ', City=' + l.City__c +
                    ', Source=' + l.Source__c +
                    ', CourseBucket=' + l.Course_Bucket__c
                );
                continue;
            }

            Id candId = leadToCandidate.get(l.Id);
            List<Activity_Log__c> logs = (candId != null) ? candidateLogsMap.get(candId) : null;

            // Last assigned SPOC (from Activity Log). Used to exclude same SPOC
            Id lastOwnerId = getLastAssignedOwner(l, logs);

            // Choose next SPOC
            Id chosenUserId = pickNextSpocId(candidates, logs, lastOwnerId);

            System.debug(LoggingLevel.INFO,
                'ReInquiryDowngradeReallocationService :: Decision LeadId=' + l.Id +
                ', CandidateId=' + candId +
                ', key=' + key +
                ', candidates=' + candidates.size() +
                ', lastAssignedOwnerId=' + lastOwnerId +
                ', chosenUserId=' + chosenUserId
            );

            if (chosenUserId == null) {
                System.debug(LoggingLevel.WARN,
                    'ReInquiryDowngradeReallocationService :: No chosen user. LeadId=' + l.Id
                );
                continue;
            }

            // Owner before change (used for Previous_Owner__c in log)
            Id previousOwnerId = l.OwnerId;

            Lead__c upd = new Lead__c(Id = l.Id);
            
            if (previousOwnerId != chosenUserId) {
                upd.OwnerId = chosenUserId;
            }
            upd.Stage__c = 'M3';   
            upd.Downgraded__c = false;

            toUpdate.add(upd);            

            // Insert Activity Log against Candidate (history is maintained on Candidate)
            Activity_Log__c a = new Activity_Log__c();
            a.Candidate__c = candId;
            a.Activity_Type__c = LOG_TYPE_OWNER_ASSIGNMENT;
            a.Changed_Date_Time__c = System.now();

            // who performed the operation (automation / running user)
            a.Action_Performed_By__c = UserInfo.getUserId();
            a.Logging_Id__c = UserInfo.getUserId();

            // audit + rotation history
            a.Previous_Owner__c = previousOwnerId;
            a.New_Owner__c = chosenUserId;

            a.Description__c =
                'Re-Inquiry reallocation. LeadId=' + l.Id +
                ', CandidateId=' + String.valueOf(candId) +
                ', City=' + l.City__c +
                ', Source=' + l.Source__c +
                ', CourseBucket=' + l.Course_Bucket__c +
                ', ExcludedLastAssignedOwner=' + String.valueOf(lastOwnerId) +
                ', PreviousOwner=' + String.valueOf(previousOwnerId) +
                ', NewOwner=' + String.valueOf(chosenUserId);

            logsToInsert.add(a);
        }

        System.debug(LoggingLevel.INFO,
            'ReInquiryDowngradeReallocationService.processReallocation :: DML Summary: LeadsToUpdate=' +
            toUpdate.size() + ', LogsToInsert=' + logsToInsert.size()
        );

        if (!toUpdate.isEmpty()) update toUpdate;
        if (!logsToInsert.isEmpty()) insert logsToInsert;

        System.debug(LoggingLevel.INFO,
            'ReInquiryDowngradeReallocationService.processReallocation :: END'
        );
    }

    // =========================
    // FETCH LOGS (Candidate-level)
    // =========================
    private static Map<Id, List<Activity_Log__c>> fetchCandidateAssignmentLogs(Set<Id> candidateIds) {
        System.debug(LoggingLevel.DEBUG,
            'ReInquiryDowngradeReallocationService.fetchCandidateAssignmentLogs :: candidateIds=' +
            (candidateIds == null ? 0 : candidateIds.size())
        );

        Map<Id, List<Activity_Log__c>> candidateLogsMap = new Map<Id, List<Activity_Log__c>>();

        if (candidateIds == null || candidateIds.isEmpty()) return candidateLogsMap;

        for (Activity_Log__c log : [
            SELECT Id, Candidate__c, Changed_Date_Time__c,
                   Previous_Owner__c, New_Owner__c,
                   Action_Performed_By__c, Activity_Type__c
            FROM Activity_Log__c
            WHERE Candidate__c IN :candidateIds
              AND Activity_Type__c = :LOG_TYPE_OWNER_ASSIGNMENT
            ORDER BY Changed_Date_Time__c DESC
        ]) {
            if (!candidateLogsMap.containsKey(log.Candidate__c)) {
                candidateLogsMap.put(log.Candidate__c, new List<Activity_Log__c>());
            }
            candidateLogsMap.get(log.Candidate__c).add(log);
        }

        System.debug(LoggingLevel.DEBUG,
            'ReInquiryDowngradeReallocationService.fetchCandidateAssignmentLogs :: mapKeys=' +
            candidateLogsMap.keySet().size()
        );
        return candidateLogsMap;
    }

    // =========================
    // BUILD POOL FROM ROUND ROBIN POOL
    // =========================
    private static Map<String, List<Id>> buildSpocPoolFromRR(List<Lead__c> leads) {
        System.debug(LoggingLevel.INFO,
            'ReInquiryDowngradeReallocationService.buildSpocPoolFromRR :: START'
        );

        Map<String, List<Id>> m = new Map<String, List<Id>>();

        Set<String> cities = new Set<String>();
        Set<String> sources = new Set<String>();
        Set<String> courseBuckets = new Set<String>();

        for (Lead__c l : leads) {
            if (!String.isBlank(l.City__c)) cities.add(l.City__c);
            if (!String.isBlank(l.Source__c)) sources.add(l.Source__c);
            if (!String.isBlank(l.Course_Bucket__c)) courseBuckets.add(l.Course_Bucket__c);
        }

        System.debug(LoggingLevel.DEBUG,
            'ReInquiryDowngradeReallocationService.buildSpocPoolFromRR :: Filters => cities=' + cities.size() +
            ', sources=' + sources.size() +
            ', courseBuckets=' + courseBuckets.size()
        );

        List<Round_Robin_Pool__c> pools = [
            SELECT Id, City__c, Lead_Source__c, Course_Bucket__c,
                   Active__c, Type__c, Assigned_Weight__c,
                   Sales_Rep__c, Sequence__c
            FROM Round_Robin_Pool__c
            WHERE Active__c = true
              AND Type__c = :RR_TYPE_ROUND_ROBIN
              AND Assigned_Weight__c > 0
              AND City__c IN :cities
              AND Lead_Source__c IN :sources
              AND Course_Bucket__c IN :courseBuckets
              AND Sales_Rep__c != null
            ORDER BY City__c, Lead_Source__c, Course_Bucket__c, Sequence__c ASC
        ];

        System.debug(LoggingLevel.INFO,
            'ReInquiryDowngradeReallocationService.buildSpocPoolFromRR :: RR records fetched=' + pools.size()
        );

        for (Round_Robin_Pool__c rr : pools) {
            String key = getKey(rr.City__c, rr.Lead_Source__c, rr.Course_Bucket__c);
            if (!m.containsKey(key)) m.put(key, new List<Id>());
            m.get(key).add(rr.Sales_Rep__c);
        }

        System.debug(LoggingLevel.INFO,
            'ReInquiryDowngradeReallocationService.buildSpocPoolFromRR :: Built keys=' + m.keySet().size()
        );
        System.debug(LoggingLevel.INFO,
            'ReInquiryDowngradeReallocationService.buildSpocPoolFromRR :: END'
        );
        return m;
    }

    private static String getKey(String city, String source, String courseBucket) {
        return String.valueOf(city) + '|' + String.valueOf(source) + '|' + String.valueOf(courseBucket);
    }

    // =========================
    // HISTORY HELPERS
    // =========================
    private static Id getLastAssignedOwner(Lead__c l, List<Activity_Log__c> logs) {
        // Latest log is first due to DESC sorting
        if (logs != null && !logs.isEmpty()) {
            Activity_Log__c latest = logs[0];
            if (latest.Previous_Owner__c  != null) {
                return latest.Previous_Owner__c ;
            }
        }
        // Fallback: current owner (in case no logs exist)
        return l.OwnerId;
    }

    /**
     * Picks next SPOC (UserId) from candidate list:
     *  - Excludes lastOwnerId if possible
     *  - Prefers SPOC never assigned before (no log history)
     *  - Else picks least-recently assigned (oldest Changed_Date_Time__c)
     *
     * NOTE: Candidate list order is already stable because RR pool is ordered by Sequence__c.
     *       That ordering is used naturally when there are ties / no history.
     */
    private static Id pickNextSpocId(List<Id> candidateUserIds, List<Activity_Log__c> logs, Id lastOwnerId) {
        if (candidateUserIds == null || candidateUserIds.isEmpty()) return null;
        if (candidateUserIds.size() == 1) return candidateUserIds[0];

        Set<Id> exclude = new Set<Id>();
        if (lastOwnerId != null) exclude.add(lastOwnerId);

        // Build "last assigned datetime" per user (latest first due to log order)
        Map<Id, Datetime> lastAssignedAt = new Map<Id, Datetime>();
        if (logs != null) {
            for (Activity_Log__c lg : logs) {
                if (lg.New_Owner__c == null) continue;
                if (!lastAssignedAt.containsKey(lg.New_Owner__c)) {
                    lastAssignedAt.put(lg.New_Owner__c, lg.Changed_Date_Time__c);
                }
            }
        }

        Id bestId;
        Datetime bestDt;

        for (Id uid : candidateUserIds) {
            if (exclude.contains(uid)) continue;

            Datetime dt = lastAssignedAt.get(uid);

            // First valid candidate becomes best
            if (bestId == null) {
                bestId = uid;
                bestDt = dt;
                continue;
            }

            // Prefer a user who has NEVER been assigned (dt == null)
            if (bestDt != null && dt == null) {
                bestId = uid;
                bestDt = dt;
                continue;
            }
            if (bestDt == null && dt != null) {
                continue;
            }

            // Both have dates: pick older (least recent)
            if (bestDt != null && dt != null && dt < bestDt) {
                bestId = uid;
                bestDt = dt;
            }
        }

        // If we excluded everyone (example: all candidates are lastOwner only), allow fallback
        if (bestId != null) return bestId;

        return candidateUserIds[0];
    }
}
