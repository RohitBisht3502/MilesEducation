public without sharing class EligibilityFolderService {

    // ---------------- PUBLIC API ----------------

    // Used when creating the initial folder structure from templates
    public static void createFoldersForLead(Id leadId) {
        if (leadId == null) return;

        Integer existing = [
            SELECT COUNT()
            FROM Eligibility_Folder__c
            WHERE Candidate__c = :leadId
        ];

        if (existing > 0) {
            return;
        }

        List<Eligibility_Folder_Template__c> templates = [
            SELECT Id, Name, Level__c, Folder_Type__c,
                   Qualification_Type__c, Degree_Title__c,
                   Parent_Template__c
            FROM Eligibility_Folder_Template__c
            ORDER BY Level__c ASC, Name ASC
        ];
        if (templates.isEmpty()) return;

        Map<Id, Id> templateToFolderId = new Map<Id, Id>();
        List<Eligibility_Folder__c> foldersToInsert = new List<Eligibility_Folder__c>();

        for (Eligibility_Folder_Template__c tpl : templates) {
            Eligibility_Folder__c f = new Eligibility_Folder__c();
            f.Name                  = tpl.Name;
            f.Candidate__c          = leadId;
            f.Level__c              = tpl.Level__c;
            f.Folder_Type__c        = tpl.Folder_Type__c;
            f.Qualification_Type__c = tpl.Qualification_Type__c;
            f.Degree_Title__c       = tpl.Degree_Title__c;
            f.Template__c           = tpl.Id;

            if (tpl.Folder_Type__c == 'Degree') {
                f.Status__c = 'Pending review';
            }

            foldersToInsert.add(f);
        }

        insert foldersToInsert;

        for (Integer i = 0; i < templates.size(); i++) {
            templateToFolderId.put(templates[i].Id, foldersToInsert[i].Id);
        }

        List<Eligibility_Folder__c> foldersToUpdate = new List<Eligibility_Folder__c>();
        for (Eligibility_Folder_Template__c tpl : templates) {
            if (tpl.Parent_Template__c == null) continue;

            Id childId  = templateToFolderId.get(tpl.Id);
            Id parentId = templateToFolderId.get(tpl.Parent_Template__c);
            if (childId != null && parentId != null) {
                foldersToUpdate.add(new Eligibility_Folder__c(
                    Id = childId,
                    Parent_Folder__c = parentId
                ));
            }
        }
        if (!foldersToUpdate.isEmpty()) {
            update foldersToUpdate;
        }

        generateEligibilityCodeForLead(leadId);
    }

    // Older 3-arg signature (kept for compatibility)
    public static Eligibility_Folder__c findDegreeFolder(
        Id leadId,
        String qualificationType,
        String degreeTitle
    ) {
        List<Eligibility_Folder__c> degList = [
            SELECT Id, Status__c, Parent_Folder__c, Month_Year__c
            FROM Eligibility_Folder__c
            WHERE Candidate__c = :leadId
              AND Qualification_Type__c = :qualificationType
              AND Degree_Title__c = :degreeTitle
              AND Folder_Type__c = 'Degree'
            LIMIT 1
        ];
        return degList.isEmpty() ? null : degList[0];
    }

    // New 4-arg signature used by API handler – currently ignores monthYear for lookup
    public static Eligibility_Folder__c findDegreeFolder(
        Id leadId,
        String qualificationType,
        String degreeTitle,
        String qualificationMonthYear
    ) {
        // If you later want to discriminate by Month_Year__c, adjust the query here.
        return findDegreeFolder(leadId, qualificationType, degreeTitle);
    }

    public static Eligibility_Folder__c findCategoryFolderForDoc(
        Id leadId,
        String qualificationType,
        String degreeTitle,
        String fileType
    ) {
        String folderType;
        if (fileType != null && fileType.toLowerCase() == 'certificate') {
            folderType = 'Certificates';
        } else if (fileType != null && fileType.toLowerCase() == 'marksheet') {
            folderType = 'Marksheets';
        }

        List<Eligibility_Folder__c> cs = [
            SELECT Id, Parent_Folder__c
            FROM Eligibility_Folder__c
            WHERE Candidate__c = :leadId
              AND Qualification_Type__c = :qualificationType
              AND Degree_Title__c = :degreeTitle
              AND Folder_Type__c = :folderType
            LIMIT 1
        ];
        return cs.isEmpty() ? null : cs[0];
    }

    public static Eligibility_Folder__c createDynamicDegreeFolders(
        Id leadId,
        String qualificationType,
        String degreeTitle
    ) {
        // Level 1 – Qualification Type folder (UG / PG / etc.)
        Eligibility_Folder__c typeFolder;
        List<Eligibility_Folder__c> existingType = [
            SELECT Id
            FROM Eligibility_Folder__c
            WHERE Candidate__c = :leadId
              AND Folder_Type__c = 'QualificationType'
              AND Qualification_Type__c = :qualificationType
            LIMIT 1
        ];
        if (existingType.isEmpty()) {
            typeFolder = new Eligibility_Folder__c(
                Name                  = qualificationType,
                Candidate__c          = leadId,
                Level__c              = '1',
                Folder_Type__c        = 'QualificationType',
                Qualification_Type__c = qualificationType
            );
            insert typeFolder;
        } else {
            typeFolder = existingType[0];
        }

        // Level 2 – Degree folder
        Eligibility_Folder__c degreeFolder = new Eligibility_Folder__c(
            Name                  = degreeTitle,
            Candidate__c          = leadId,
            Level__c              = '2',
            Folder_Type__c        = 'Degree',
            Qualification_Type__c = qualificationType,
            Degree_Title__c       = degreeTitle,
            Parent_Folder__c      = typeFolder.Id,
            Status__c             = 'Pending review'
        );
        insert degreeFolder;

        // Level 3 – Certificates / Marksheets under degree
        Eligibility_Folder__c certFolder = new Eligibility_Folder__c(
            Name                  = 'Certificates',
            Candidate__c          = leadId,
            Level__c              = '3',
            Folder_Type__c        = 'Certificates',
            Qualification_Type__c = qualificationType,
            Degree_Title__c       = degreeTitle,
            Parent_Folder__c      = degreeFolder.Id
        );
        Eligibility_Folder__c marksFolder = new Eligibility_Folder__c(
            Name                  = 'Marksheets',
            Candidate__c          = leadId,
            Level__c              = '3',
            Folder_Type__c        = 'Marksheets',
            Qualification_Type__c = qualificationType,
            Degree_Title__c       = degreeTitle,
            Parent_Folder__c      = degreeFolder.Id
        );

        insert new List<Eligibility_Folder__c>{ certFolder, marksFolder };

        return degreeFolder;
    }

    public static void setAllFoldersToPendingReviewForLead(Id leadId) {
        if (leadId == null) return;

        List<Eligibility_Folder__c> folders = [
            SELECT Id, Status__c
            FROM Eligibility_Folder__c
            WHERE Candidate__c = :leadId
        ];
        if (folders.isEmpty()) return;

        List<Eligibility_Folder__c> updates = new List<Eligibility_Folder__c>();
        for (Eligibility_Folder__c f : folders) {
            if (f.Status__c != 'Pending review') {
                updates.add(new Eligibility_Folder__c(
                    Id = f.Id,
                    Status__c = 'Pending review'
                ));
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    /**
     * Called from controller when a single folder is updated manually via LWC
     * (status/comment change).
     * - Creates a Task for Lead owner when status changes
     * - Creates a Task for comment change (if only comment changed)
     * - Recalculates Lead.GP_Lead_Status__c from folder statuses
     */
    public static void handleSingleFolderUpdate(
        Eligibility_Folder__c oldRec,
        Eligibility_Folder__c newRec
    ) {
        if (oldRec == null || newRec == null) return;
        if (newRec.Candidate__c == null) return;

        // Only degree (eligibility title) folders allow status/comment updates
        if (oldRec.Folder_Type__c != 'Degree') {
            return;
        }

        Set<Id> leadIds = new Set<Id>{ newRec.Candidate__c };
        List<Task> tasks = new List<Task>();

        Boolean statusChanged  = oldRec.Status__c   != newRec.Status__c;
        Boolean commentChanged = oldRec.Comments__c != newRec.Comments__c;

        if (statusChanged || commentChanged) {
            Lead l = [
                SELECT Id, OwnerId
                FROM Lead
                WHERE Id = :newRec.Candidate__c
                LIMIT 1
            ];
            if (l.OwnerId != null) {
                Task t = new Task();
                t.OwnerId = l.OwnerId;
                t.WhoId   = l.Id;
                t.ActivityDate = System.today();

                if (statusChanged && newRec.Status__c != 'Approved') {
                    t.Subject = 'Eligibility folder status updated - ' +
                        (String.isNotBlank(newRec.Name) ? newRec.Name : 'Folder');
                    t.Status   = 'Not Started';
                    t.Priority = 'High';
                    t.Description =
                        'Folder "' + (String.isNotBlank(newRec.Name) ? newRec.Name : String.valueOf(newRec.Id)) +
                        '" status changed from "' + (oldRec.Status__c != null ? oldRec.Status__c : 'None') +
                        '" to "' + (newRec.Status__c != null ? newRec.Status__c : 'None') + '".' +
                        (String.isNotBlank(newRec.Comments__c)
                            ? '\nReviewer comment: ' + newRec.Comments__c
                            : '');
                } else if (commentChanged) {
                    t.Subject = 'Eligibility folder comment added - ' +
                        (String.isNotBlank(newRec.Name) ? newRec.Name : 'Folder');
                    t.Status   = 'Not Started';
                    t.Priority = 'Normal';
                    t.Description =
                        'Comment updated on folder "' +
                        (String.isNotBlank(newRec.Name) ? newRec.Name : String.valueOf(newRec.Id)) +
                        '": ' +
                        (newRec.Comments__c != null ? newRec.Comments__c : '');
                }

                tasks.add(t);
            }
        }

        if (!tasks.isEmpty()) {
            insert tasks;
        }

        updateLeadStatusForLeads(leadIds);
    }

    /**
     * Recalculate Lead.GP_Lead_Status__c for leads whose files changed.
     * IMPORTANT: does NOT update any folder Status__c.
     */
    public static void recalcFromFiles(Set<Id> fileIds) {
        if (fileIds == null || fileIds.isEmpty()) return;

        Set<Id> leadIds = new Set<Id>();
        for (Eligibility_File__c f : [
            SELECT Candidate__c
            FROM Eligibility_File__c
            WHERE Id IN :fileIds
              AND Candidate__c != null
        ]) {
            leadIds.add(f.Candidate__c);
        }

        if (!leadIds.isEmpty()) {
            updateLeadStatusForLeads(leadIds);
        }
    }

    /**
     * Recalculate Lead.GP_Lead_Status__c given affected folder Ids.
     * IMPORTANT: no automatic folder.Status__c changes are done here.
     */
    public static void recalcFromFileFolders(Set<Id> folderIds) {
        if (folderIds == null || folderIds.isEmpty()) return;

        Set<Id> leadIds = new Set<Id>();
        for (Eligibility_Folder__c f : [
            SELECT Candidate__c
            FROM Eligibility_Folder__c
            WHERE Id IN :folderIds
              AND Candidate__c != null
        ]) {
            leadIds.add(f.Candidate__c);
        }

        if (!leadIds.isEmpty()) {
            updateLeadStatusForLeads(leadIds);
        }
    }

    // Backward-compat alias – some old code might still call this
    public static void recalcDegreeStatusByFile(Set<Id> fileIds) {
        recalcFromFiles(fileIds);
    }

    // ---------------- LEAD STATUS AGGREGATION ----------------

    /**
     * UPDATED LOGIC:
     * - All Degree folders Approved -> Verified
     * - All files Verified -> Verified
     * - All files Not Applicable -> Not Eligible
     * - Any files present -> Under Verification
     * - Otherwise keep existing status (Initiated / Yet to Initiate)
     */

    /**
     * Aggregates folder.Status__c for each Lead and sets Lead.GP_Lead_Status__c:
     * - If any folder = 'Recheck'      → 'Recheck'
     * - Else if all folders = 'All Good' → 'Verified'
     * - Else if all folders = 'Pending Review' → 'New lead'
     * - Else                             → 'Verification'
     */
    private static void updateLeadStatusForLeads(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) return;

        Map<Id, List<Eligibility_File__c>> filesByLead = new Map<Id, List<Eligibility_File__c>>();
        for (Eligibility_File__c f : [
            SELECT Id, Candidate__c, Status__c
            FROM Eligibility_File__c
            WHERE Candidate__c IN :leadIds
        ]) {
            if (!filesByLead.containsKey(f.Candidate__c)) {
                filesByLead.put(f.Candidate__c, new List<Eligibility_File__c>());
            }
            filesByLead.get(f.Candidate__c).add(f);
        }

        Map<Id, List<Eligibility_Folder__c>> degreeFoldersByLead = new Map<Id, List<Eligibility_Folder__c>>();
        for (Eligibility_Folder__c f : [
            SELECT Id, Candidate__c, Status__c
            FROM Eligibility_Folder__c
            WHERE Candidate__c IN :leadIds
              AND Folder_Type__c = 'Degree'
        ]) {
            if (!degreeFoldersByLead.containsKey(f.Candidate__c)) {
                degreeFoldersByLead.put(f.Candidate__c, new List<Eligibility_Folder__c>());
            }
            degreeFoldersByLead.get(f.Candidate__c).add(f);
        }

        Map<Id, Lead> existingLeads = new Map<Id, Lead>([
            SELECT Id, GP_Lead_Status__c
            FROM Lead
            WHERE Id IN :leadIds
        ]);

        List<Lead> updates = new List<Lead>();

        for (Id lid : leadIds) {
            List<Eligibility_File__c> flist = filesByLead.get(lid);
            Boolean hasFiles = flist != null && !flist.isEmpty();
            Boolean allFilesVerified = hasFiles;
            Boolean allFilesNotApplicable = hasFiles;

            if (hasFiles) {
                for (Eligibility_File__c f : flist) {
                    String s = f.Status__c;
                    if (s == null || !s.equalsIgnoreCase('Verified')) {
                        allFilesVerified = false;
                    }
                    if (s == null || (!s.equalsIgnoreCase('Not Applicable') && !s.equalsIgnoreCase('Not application'))) {
                        allFilesNotApplicable = false;
                    }
                }
            }

            List<Eligibility_Folder__c> degFolders = degreeFoldersByLead.get(lid);
            Boolean hasDegreeFolders = degFolders != null && !degFolders.isEmpty();
            Boolean allFoldersApproved = hasDegreeFolders;
            if (hasDegreeFolders) {
                for (Eligibility_Folder__c df : degFolders) {
                    if (df.Status__c == null || !df.Status__c.equalsIgnoreCase('Approved')) {
                        allFoldersApproved = false;
                        break;
                    }
                }
            }

            String newStatus = null;
            if (allFoldersApproved) {
                newStatus = 'Verified';
            } else if (hasFiles && allFilesNotApplicable) {
                newStatus = 'Not Eligible';
            } else if (hasFiles && allFilesVerified) {
                newStatus = 'Verified';
            } else if (hasFiles) {
                newStatus = 'Under Verification';
            }

            Lead existing = existingLeads.get(lid);
            if (existing == null) continue;
            if (String.isBlank(newStatus) || existing.GP_Lead_Status__c == newStatus) continue;

            updates.add(new Lead(
                Id = lid,
                GP_Lead_Status__c = newStatus
            ));
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }

    // ---------------- ELIGIBILITY CODE ----------------

    private static void generateEligibilityCodeForLead(Id leadId) {
        if (leadId == null) return;

        Lead l = [
            SELECT Id, City__c, Eligibility_Code__c, CreatedDate
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];

        if (!String.isBlank(l.Eligibility_Code__c)) {
            return;
        }

        Date today = Date.today();

        String cityCode = 'NA';
        if (!String.isBlank(l.City__c)) {
            String c = l.City__c.trim().toUpperCase();
            cityCode = c.length() >= 3 ? c.substring(0, 3) : c;
        }

        Integer countToday = [
            SELECT COUNT()
            FROM Lead
            WHERE Eligibility_Code__c != null
              AND CreatedDate = TODAY
        ];
        Integer seq = countToday + 1;

        String code = 'Eligibility/' +
                      cityCode + '/' +
                      String.valueOf(today.day()) + '/' +
                      String.valueOf(today.month()) + '/' +
                      String.valueOf(seq);

        update new Lead(
            Id = l.Id,
            Eligibility_Code__c = code
        );
    }
}