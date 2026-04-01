public with sharing class CandidateProgramWorkbenchController {

    public class ReallocationRequest {
        @AuraEnabled public List<Id> candidateIds;
        @AuraEnabled public Id targetOwnerId;
        @AuraEnabled public String comment;
    }

    public class FilterRequest {
        @AuraEnabled public String createdFrom;
        @AuraEnabled public String createdTo;
        @AuraEnabled public String firstInquiryFrom;
        @AuraEnabled public String firstInquiryTo;
        @AuraEnabled public String lastInquiryFrom;
        @AuraEnabled public String lastInquiryTo;
        @AuraEnabled public List<String> firstInquirySources;
        @AuraEnabled public List<String> lastInquirySources;
        @AuraEnabled public List<String> levelKeys;
        @AuraEnabled public List<String> spocIds;
        @AuraEnabled public List<String> cities;
        @AuraEnabled public String callActivityType;
        @AuraEnabled public String callFrom;
        @AuraEnabled public String callTo;
    }

    public class WorkbenchResponse {
        @AuraEnabled public List<CandidateRow> rows;
        @AuraEnabled public List<FilterOption> spocOptions;
        @AuraEnabled public List<LevelGroup> levelGroups;
        @AuraEnabled public List<FilterOption> enquirySourceOptions;
        @AuraEnabled public List<FilterOption> cityOptions;
    }

    public class CandidateRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Id spocId;
        @AuraEnabled public String name;
        @AuraEnabled public String candidateId;
        @AuraEnabled public String createdDate;
        @AuraEnabled public String firstInquiryDate;
        @AuraEnabled public String firstInquirySource;
        @AuraEnabled public String status;
        @AuraEnabled public String statusClass;
        @AuraEnabled public String spoc;
        @AuraEnabled public String city;
        @AuraEnabled public String lastInquiry;
        @AuraEnabled public String lastInquirySource;
        @AuraEnabled public String callStatus;
        @AuraEnabled public String callStatusClass;
        @AuraEnabled public Boolean expanded;
        @AuraEnabled public List<RelatedLeadRow> relatedLeads;
    }

    public class RelatedLeadRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String course;
        @AuraEnabled public String level;
    }

    public class FilterOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public FilterOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class LevelGroup {
        @AuraEnabled public String course;
        @AuraEnabled public List<FilterOption> options;

        public LevelGroup(String course) {
            this.course = course;
            this.options = new List<FilterOption>();
        }
    }

    @AuraEnabled
    public static WorkbenchResponse getWorkbenchData(FilterRequest request) {
        WorkbenchResponse response = new WorkbenchResponse();
        response.rows = new List<CandidateRow>();
        response.spocOptions = new List<FilterOption>();
        response.levelGroups = new List<LevelGroup>();
        response.enquirySourceOptions = new List<FilterOption>();
        response.cityOptions = new List<FilterOption>();

        for (Schema.PicklistEntry cityEntry : Schema.SObjectType.Round_Robin_Pool__c.fields.City__c.getPicklistValues()) {
            if (cityEntry.isActive()) {
                response.cityOptions.add(new FilterOption(cityEntry.getLabel(), cityEntry.getValue()));
            }
        }

        Set<Id> subordinateIds = getSubordinateUserIds();
        if (subordinateIds.isEmpty()) {
            return response;
        }

        for (User spoc : [
            SELECT Id, Name
            FROM User
            WHERE Id IN :subordinateIds
            ORDER BY Name
        ]) {
            response.spocOptions.add(new FilterOption(spoc.Name, String.valueOf(spoc.Id)));
        }

        Date createdFrom = parseDateOnly(request != null ? request.createdFrom : null);
        Date createdTo = parseDateOnly(request != null ? request.createdTo : null);
        Set<Id> selectedSpocIds = new Set<Id>();
        if (request != null && request.spocIds != null) {
            for (String spocIdValue : request.spocIds) {
                if (String.isNotBlank(spocIdValue)) {
                    try {
                        selectedSpocIds.add((Id) spocIdValue);
                    } catch (Exception e) {
                    }
                }
            }
        }
        if (!selectedSpocIds.isEmpty()) {
            subordinateIds.retainAll(selectedSpocIds);
        }
        if (subordinateIds.isEmpty()) {
            return response;
        }

        Set<String> selectedCities = new Set<String>();
        if (request != null && request.cities != null) {
            selectedCities.addAll(request.cities);
        }

        List<Lead> candidates = [
            SELECT Id, Name, Candidate_ID__c, OwnerId, Owner.Name, CreatedDate, City__c
            FROM Lead
            WHERE OwnerId IN :subordinateIds
            AND (Is_Merged__c = false OR Is_Merged__c = null)
            ORDER BY CreatedDate DESC
            LIMIT 500
        ];

        Map<Id, Lead> candidateById = new Map<Id, Lead>();
        for (Lead candidate : candidates) {
            if (createdFrom != null && candidate.CreatedDate.date() < createdFrom) continue;
            if (createdTo != null && candidate.CreatedDate.date() > createdTo) continue;
            if (!selectedCities.isEmpty() && !selectedCities.contains(candidate.City__c)) continue;
            candidateById.put(candidate.Id, candidate);
        }

        if (candidateById.isEmpty()) {
            return response;
        }

        Map<Id, List<Lead__c>> relatedLeadsByCandidate = new Map<Id, List<Lead__c>>();
        Map<String, Set<String>> levelsByCourse = new Map<String, Set<String>>();
        for (Lead__c relatedLead : [
            SELECT Id, Candidate__c, Course__c, Stage__c, CreatedDate
            FROM Lead__c
            WHERE Candidate__c IN :candidateById.keySet()
            ORDER BY CreatedDate DESC
        ]) {
            if (!relatedLeadsByCandidate.containsKey(relatedLead.Candidate__c)) {
                relatedLeadsByCandidate.put(relatedLead.Candidate__c, new List<Lead__c>());
            }
            relatedLeadsByCandidate.get(relatedLead.Candidate__c).add(relatedLead);

            if (String.isNotBlank(relatedLead.Course__c) && String.isNotBlank(relatedLead.Stage__c)) {
                if (!levelsByCourse.containsKey(relatedLead.Course__c)) {
                    levelsByCourse.put(relatedLead.Course__c, new Set<String>());
                }
                levelsByCourse.get(relatedLead.Course__c).add(relatedLead.Stage__c);
            }
        }

        List<String> sortedCourses = new List<String>();
        sortedCourses.addAll(levelsByCourse.keySet());
        sortedCourses.sort();
        for (String course : sortedCourses) {
            LevelGroup levelGroup = new LevelGroup(course);
            List<String> levels = new List<String>();
            levels.addAll(levelsByCourse.get(course));
            levels.sort();
            for (String level : levels) {
                levelGroup.options.add(new FilterOption(level, buildLevelKey(course, level)));
            }
            response.levelGroups.add(levelGroup);
        }

        Set<String> selectedLevelKeys = request != null && request.levelKeys != null
            ? new Set<String>(request.levelKeys)
            : new Set<String>();
        Set<String> firstInquirySources = request != null && request.firstInquirySources != null
            ? new Set<String>(request.firstInquirySources)
            : new Set<String>();
        Set<String> lastInquirySources = request != null && request.lastInquirySources != null
            ? new Set<String>(request.lastInquirySources)
            : new Set<String>();
        Date firstInquiryFrom = parseDateOnly(request != null ? request.firstInquiryFrom : null);
        Date firstInquiryTo = parseDateOnly(request != null ? request.firstInquiryTo : null);
        Date lastInquiryFrom = parseDateOnly(request != null ? request.lastInquiryFrom : null);
        Date lastInquiryTo = parseDateOnly(request != null ? request.lastInquiryTo : null);

        Datetime callFrom = parseDateTimeLocal(request != null ? request.callFrom : null);
        Datetime callTo = parseDateTimeLocal(request != null ? request.callTo : null);
        String callActivityType = request != null ? request.callActivityType : null;

        Map<Id, List<Enquiry__c>> enquiriesByCandidate = new Map<Id, List<Enquiry__c>>();
        Set<String> enquirySources = new Set<String>();
        for (Enquiry__c enquiry : [
            SELECT Id, Candidate__c, CreatedDate, Coming_From__c
            FROM Enquiry__c
            WHERE Candidate__c IN :candidateById.keySet()
            ORDER BY CreatedDate ASC
        ]) {
            if (!enquiriesByCandidate.containsKey(enquiry.Candidate__c)) {
                enquiriesByCandidate.put(enquiry.Candidate__c, new List<Enquiry__c>());
            }
            enquiriesByCandidate.get(enquiry.Candidate__c).add(enquiry);
            if (String.isNotBlank(enquiry.Coming_From__c)) {
                enquirySources.add(enquiry.Coming_From__c);
            }
        }

        List<String> sortedEnquirySources = new List<String>();
        sortedEnquirySources.addAll(enquirySources);
        sortedEnquirySources.sort();
        for (String enquirySource : sortedEnquirySources) {
            response.enquirySourceOptions.add(new FilterOption(enquirySource, enquirySource));
        }

        Map<Id, List<Call_Log__c>> callLogsByCandidate = new Map<Id, List<Call_Log__c>>();
        for (Call_Log__c callLog : [
            SELECT Id, Candidate__c, CreatedDate, Start_Time__c, L1__c
            FROM Call_Log__c
            WHERE Candidate__c IN :candidateById.keySet()
            ORDER BY CreatedDate DESC
        ]) {
            if (!callLogsByCandidate.containsKey(callLog.Candidate__c)) {
                callLogsByCandidate.put(callLog.Candidate__c, new List<Call_Log__c>());
            }
            callLogsByCandidate.get(callLog.Candidate__c).add(callLog);
        }

        for (Lead candidate : candidateById.values()) {
            List<Lead__c> relatedLeads = relatedLeadsByCandidate.containsKey(candidate.Id)
                ? relatedLeadsByCandidate.get(candidate.Id)
                : new List<Lead__c>();
            List<Enquiry__c> candidateEnquiries = enquiriesByCandidate.containsKey(candidate.Id)
                ? enquiriesByCandidate.get(candidate.Id)
                : new List<Enquiry__c>();

            if (!matchesLevelFilter(relatedLeads, selectedLevelKeys)) {
                continue;
            }
            if (!matchesInquiryFilter(candidateEnquiries, firstInquiryFrom, firstInquiryTo, lastInquiryFrom, lastInquiryTo, firstInquirySources, lastInquirySources)) {
                continue;
            }

            List<Call_Log__c> candidateCallLogs = callLogsByCandidate.containsKey(candidate.Id)
                ? callLogsByCandidate.get(candidate.Id)
                : new List<Call_Log__c>();

            if (!matchesCallActivityFilter(candidateCallLogs, callActivityType, callFrom, callTo)) {
                continue;
            }

            CandidateRow row = new CandidateRow();
            row.id = candidate.Id;
            row.spocId = candidate.OwnerId;
            row.name = candidate.Name;
            row.candidateId = candidate.Candidate_ID__c;
            row.createdDate = formatDate(candidate.CreatedDate);
            row.firstInquiryDate = formatDate(getFirstInquiryDate(candidateEnquiries));
            row.firstInquirySource = getFirstInquirySource(candidateEnquiries);
            row.spoc = candidate.Owner != null ? candidate.Owner.Name : 'Unassigned';
            row.city = candidate.City__c;
            row.lastInquiry = formatDate(getLastEnquiryDate(candidateEnquiries, getLastInquiryDate(relatedLeads, candidate.CreatedDate)));
            row.lastInquirySource = getLastInquirySource(candidateEnquiries);
            row.expanded = false;
            row.relatedLeads = new List<RelatedLeadRow>();

            for (Lead__c relatedLead : relatedLeads) {
                RelatedLeadRow relatedRow = new RelatedLeadRow();
                relatedRow.id = relatedLead.Id;
                relatedRow.course = relatedLead.Course__c;
                relatedRow.level = relatedLead.Stage__c;
                row.relatedLeads.add(relatedRow);
            }

            applyCallStatus(row, candidateCallLogs);
            applyTemperature(row, relatedLeads, candidate.CreatedDate);
            response.rows.add(row);
        }

        return response;
    }

    @AuraEnabled
    public static void reallocateCandidates(List<Id> candidateIds, Id targetOwnerId, String comment) {
        if (candidateIds == null || candidateIds.isEmpty()) {
            throw new AuraHandledException('Please select at least one candidate.');
        }
        if (targetOwnerId == null) {
            throw new AuraHandledException('Please select a SPOC.');
        }
        if (String.isBlank(comment)) {
            throw new AuraHandledException('Please enter reallocation comments.');
        }

        Set<Id> allowedSpocIds = getSubordinateUserIds();
        if (!allowedSpocIds.contains(targetOwnerId)) {
            throw new AuraHandledException('You can reallocate only to your SPOC users.');
        }

        User targetOwner = [
            SELECT Id, Name
            FROM User
            WHERE Id = :targetOwnerId
            LIMIT 1
        ];

        List<Lead> candidatesToUpdate = [
            SELECT Id, Name, OwnerId, Owner.Name
            FROM Lead
            WHERE Id IN :candidateIds
        ];

        Map<Id, Lead> oldLeadMap = new Map<Id, Lead>();
        List<Lead> changedCandidates = new List<Lead>();
        List<Activity_Log__c> activityLogs = new List<Activity_Log__c>();
        Datetime changedOn = System.now();
        String trimmedComment = comment != null ? comment.trim() : null;

        for (Lead candidate : candidatesToUpdate) {
            if (candidate.OwnerId == targetOwnerId) {
                continue;
            }

            String previousOwnerName = candidate.Owner != null ? candidate.Owner.Name : 'Unknown';
            Lead oldCandidate = candidate.clone(true, true, true, true);
            oldLeadMap.put(candidate.Id, oldCandidate);
            candidate.OwnerId = targetOwnerId;
            changedCandidates.add(candidate);

            ActivityLogService.Request logRequest = new ActivityLogService.Request();
            logRequest.name = 'Candidate Reallocated';
            logRequest.activityType = 'Candidate Reallocation';
            logRequest.description = 'Candidate reallocated from ' + previousOwnerName + ' to ' + targetOwner.Name + '.';
            logRequest.createdBy = UserInfo.getName();
            logRequest.changedDateTime = changedOn;
            logRequest.actionPerformedBy = UserInfo.getUserId();
            logRequest.loggingId = candidate.Id;
            logRequest.candidateId = candidate.Id;
            logRequest.previousOwnerId = oldCandidate.OwnerId;
            logRequest.newOwnerId = targetOwnerId;
            logRequest.extraFields.put('Reason_For_Change__c', trimmedComment);
            activityLogs.add(ActivityLogService.createLog(logRequest));
        }

        if (changedCandidates.isEmpty()) {
            return;
        }

        update changedCandidates;
        // Get Notification Type Id
Id notifTypeId = [
    SELECT Id 
    FROM CustomNotificationType 
    WHERE DeveloperName = 'Lead_Assigned_by_GM' 
    LIMIT 1
].Id;

// Prepare recipient (SPOC)
Set<String> recipientIds = new Set<String>{
    String.valueOf(targetOwnerId)
};

// Send notification for each lead
for (Lead leadRec : changedCandidates) {
    Messaging.CustomNotification notification = new Messaging.CustomNotification();

    notification.setTitle('New Lead Assigned');
    notification.setBody(
        'GM ' + UserInfo.getName() + 
        ' has assigned you a lead: ' + leadRec.Name
    );

    notification.setNotificationTypeId(notifTypeId);
    notification.setTargetId(leadRec.Id);

    notification.send(recipientIds);
}
        LeadRelatedSyncService.syncRelatedLeadsOnCandidateOwnerChange(changedCandidates, oldLeadMap);
        ActivityLogService.insertLogs(activityLogs);
    }

    private static Set<Id> getSubordinateUserIds() {
        Set<Id> subordinateIds = new Set<Id>();
        for (User userRecord : [
            SELECT Id
            FROM User
            WHERE ManagerId = :UserInfo.getUserId()
            AND IsActive = true
        ]) {
            subordinateIds.add(userRecord.Id);
        }
        return subordinateIds;
    }

    private static Boolean matchesLevelFilter(List<Lead__c> relatedLeads, Set<String> selectedLevelKeys) {
        if (selectedLevelKeys == null || selectedLevelKeys.isEmpty()) {
            return true;
        }
        for (Lead__c relatedLead : relatedLeads) {
            String relatedLeadKey = buildLevelKey(relatedLead.Course__c, relatedLead.Stage__c);
            if (selectedLevelKeys.contains(relatedLeadKey)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean matchesCallActivityFilter(
        List<Call_Log__c> callLogs,
        String callActivityType,
        Datetime callFrom,
        Datetime callTo
    ) {
        if (String.isBlank(callActivityType)) {
            return true;
        }
        if (callFrom == null || callTo == null) {
            return true;
        }

        List<Call_Log__c> logsInRange = new List<Call_Log__c>();
        for (Call_Log__c callLog : callLogs) {
            Datetime activityTime = callLog.Start_Time__c != null ? callLog.Start_Time__c : callLog.CreatedDate;
            if (activityTime != null && activityTime >= callFrom && activityTime <= callTo) {
                logsInRange.add(callLog);
            }
        }

        if (callActivityType == 'notDialed') {
            return logsInRange.isEmpty();
        }
        if (callActivityType == 'connected') {
            for (Call_Log__c callLog : logsInRange) {
                if (callLog.L1__c == 'Connected') {
                    return true;
                }
            }
            return false;
        }
        if (callActivityType == 'notConnected') {
            for (Call_Log__c callLog : logsInRange) {
                if (callLog.L1__c == 'Not-Connected') {
                    return true;
                }
            }
            return false;
        }
        return true;
    }

    private static Boolean matchesInquiryFilter(
        List<Enquiry__c> enquiries,
        Date firstInquiryFrom,
        Date firstInquiryTo,
        Date lastInquiryFrom,
        Date lastInquiryTo,
        Set<String> firstInquirySources,
        Set<String> lastInquirySources
    ) {
        Enquiry__c firstInquiry = getFirstInquiry(enquiries);
        Enquiry__c lastInquiry = getLastInquiry(enquiries);

        if ((firstInquiryFrom != null || firstInquiryTo != null || !firstInquirySources.isEmpty()) && firstInquiry == null) {
            return false;
        }
        if ((lastInquiryFrom != null || lastInquiryTo != null || !lastInquirySources.isEmpty()) && lastInquiry == null) {
            return false;
        }

        if (firstInquiry != null) {
            Date firstInquiryDate = firstInquiry.CreatedDate.date();
            if (firstInquiryFrom != null && firstInquiryDate < firstInquiryFrom) return false;
            if (firstInquiryTo != null && firstInquiryDate > firstInquiryTo) return false;
            if (!firstInquirySources.isEmpty() && !firstInquirySources.contains(firstInquiry.Coming_From__c)) return false;
        }

        if (lastInquiry != null) {
            Date lastInquiryDate = lastInquiry.CreatedDate.date();
            if (lastInquiryFrom != null && lastInquiryDate < lastInquiryFrom) return false;
            if (lastInquiryTo != null && lastInquiryDate > lastInquiryTo) return false;
            if (!lastInquirySources.isEmpty() && !lastInquirySources.contains(lastInquiry.Coming_From__c)) return false;
        }

        return true;
    }

    private static void applyCallStatus(CandidateRow row, List<Call_Log__c> callLogs) {
        row.callStatus = 'Not dialed';
        row.callStatusClass = 'call-muted';
        if (callLogs == null || callLogs.isEmpty()) {
            return;
        }

        Call_Log__c latestCall = callLogs[0];
        if (latestCall.L1__c == 'Connected') {
            row.callStatus = 'Connected';
            row.callStatusClass = 'call-linked';
        } else if (latestCall.L1__c == 'Not-Connected') {
            row.callStatus = 'Not connected';
            row.callStatusClass = 'call-muted';
        }
    }

    private static void applyTemperature(CandidateRow row, List<Lead__c> relatedLeads, Datetime candidateCreatedDate) {
        Datetime referenceDate = getLastInquiryDate(relatedLeads, candidateCreatedDate);
        Integer ageInDays = referenceDate == null ? 999 : referenceDate.date().daysBetween(Date.today());

        if (ageInDays <= 7) {
            row.status = 'Hot';
            row.statusClass = 'status-dot hot';
        } else if (ageInDays <= 30) {
            row.status = 'Warm';
            row.statusClass = 'status-dot warm';
        } else {
            row.status = 'Cool';
            row.statusClass = 'status-dot cool';
        }
    }

    private static Datetime getLastInquiryDate(List<Lead__c> relatedLeads, Datetime fallbackDate) {
        Datetime latest = fallbackDate;
        if (relatedLeads != null) {
            for (Lead__c relatedLead : relatedLeads) {
                if (latest == null || relatedLead.CreatedDate > latest) {
                    latest = relatedLead.CreatedDate;
                }
            }
        }
        return latest;
    }

    private static Enquiry__c getFirstInquiry(List<Enquiry__c> enquiries) {
        return (enquiries == null || enquiries.isEmpty()) ? null : enquiries[0];
    }

    private static Enquiry__c getLastInquiry(List<Enquiry__c> enquiries) {
        return (enquiries == null || enquiries.isEmpty()) ? null : enquiries[enquiries.size() - 1];
    }

    private static Datetime getFirstInquiryDate(List<Enquiry__c> enquiries) {
        Enquiry__c enquiry = getFirstInquiry(enquiries);
        return enquiry == null ? null : enquiry.CreatedDate;
    }

    private static String getFirstInquirySource(List<Enquiry__c> enquiries) {
        Enquiry__c enquiry = getFirstInquiry(enquiries);
        return enquiry == null ? null : enquiry.Coming_From__c;
    }

    private static String getLastInquirySource(List<Enquiry__c> enquiries) {
        Enquiry__c enquiry = getLastInquiry(enquiries);
        return enquiry == null ? null : enquiry.Coming_From__c;
    }

    private static Datetime getLastEnquiryDate(List<Enquiry__c> enquiries, Datetime fallbackDate) {
        Enquiry__c enquiry = getLastInquiry(enquiries);
        return enquiry == null ? fallbackDate : enquiry.CreatedDate;
    }

    private static String buildLevelKey(String course, String level) {
        return normalizeFilterValue(course) + '||' + normalizeFilterValue(level);
    }

    private static String normalizeFilterValue(String value) {
        return String.isBlank(value) ? '' : value.trim().toLowerCase();
    }

    private static Date parseDateOnly(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Date.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }

    private static Datetime parseDateTimeLocal(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Datetime.valueOf(value.replace('T', ' '));
        } catch (Exception e) {
            return null;
        }
    }

   private static String formatDate(Datetime value) {
    return value == null ? null : value.format('yyyy-MM-dd');
}

}