public without sharing class EligibilityFolderService {

    // ---------------- PUBLIC API ----------------

    public static void createFoldersForLead(Id leadId) {
        if (leadId == null) return;

        Integer existing = [
            SELECT COUNT()
            FROM Eligibility_Folder__c
            WHERE Lead__c = :leadId
        ];

        if (existing > 0) {
            System.debug('EligibilityFolderService: Folders already exist for Lead ' + leadId);
            return;
        }

        List<Eligibility_Folder_Template__c> templates = [
            SELECT Id, Name, Level__c, Folder_Type__c,
                   Qualification_Type__c, Degree_Title__c,
                   Parent_Template__c
            FROM Eligibility_Folder_Template__c
            ORDER BY Level__c ASC, Name ASC
        ];

        if (templates.isEmpty()) {
            System.debug('EligibilityFolderService: No folder templates found.');
            return;
        }

        Map<Id, Id> templateIdToFolderId = new Map<Id, Id>();
        List<Eligibility_Folder__c> foldersToInsert = new List<Eligibility_Folder__c>();

        for (Eligibility_Folder_Template__c tpl : templates) {
            Eligibility_Folder__c folder = new Eligibility_Folder__c();
            folder.Name                  = tpl.Name;
            folder.Lead__c               = leadId;
            folder.Level__c              = tpl.Level__c;
            folder.Folder_Type__c        = tpl.Folder_Type__c;
            folder.Qualification_Type__c = tpl.Qualification_Type__c;
            folder.Degree_Title__c       = tpl.Degree_Title__c;
            folder.Template__c           = tpl.Id;

            if (tpl.Folder_Type__c == 'Degree') {
                folder.Status__c = 'Pending Review';
            }

            foldersToInsert.add(folder);
        }

        insert foldersToInsert;

        for (Integer i = 0; i < templates.size(); i++) {
            templateIdToFolderId.put(templates[i].Id, foldersToInsert[i].Id);
        }

        List<Eligibility_Folder__c> foldersToUpdate = new List<Eligibility_Folder__c>();
        for (Eligibility_Folder_Template__c tpl : templates) {
            if (tpl.Parent_Template__c == null) continue;
            Id folderId = templateIdToFolderId.get(tpl.Id);
            Id parentFolderId = templateIdToFolderId.get(tpl.Parent_Template__c);
            if (folderId != null && parentFolderId != null) {
                Eligibility_Folder__c f = new Eligibility_Folder__c(Id = folderId);
                f.Parent_Folder__c = parentFolderId;
                foldersToUpdate.add(f);
            }
        }
        if (!foldersToUpdate.isEmpty()) {
            update foldersToUpdate;
        }

        System.debug('EligibilityFolderService: Created ' + foldersToInsert.size() + ' folders for Lead ' + leadId);

        generateEligibilityCodeForLead(leadId);
    }

    public static Eligibility_Folder__c findDegreeFolder(
        Id leadId,
        String qualificationType,
        String degreeTitle
    ) {
        List<Eligibility_Folder__c> degList = [
            SELECT Id, Status__c, Parent_Folder__c
            FROM Eligibility_Folder__c
            WHERE Lead__c = :leadId
              AND Qualification_Type__c = :qualificationType
              AND Degree_Title__c = :degreeTitle
              AND Folder_Type__c = 'Degree'
            LIMIT 1
        ];
        return degList.isEmpty() ? null : degList[0];
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

        List<Eligibility_Folder__c> folders = [
            SELECT Id, Parent_Folder__c
            FROM Eligibility_Folder__c
            WHERE Lead__c = :leadId
              AND Qualification_Type__c = :qualificationType
              AND Degree_Title__c = :degreeTitle
              AND Folder_Type__c = :folderType
            LIMIT 1
        ];

        return folders.isEmpty() ? null : folders[0];
    }

    public static Eligibility_Folder__c createDynamicDegreeFolders(
        Id leadId,
        String qualificationType,
        String degreeTitle
    ) {
        List<Eligibility_Folder__c> typeFolders = [
            SELECT Id
            FROM Eligibility_Folder__c
            WHERE Lead__c = :leadId
              AND Folder_Type__c = 'QualificationType'
              AND Qualification_Type__c = :qualificationType
            LIMIT 1
        ];

        Eligibility_Folder__c typeFolder;
        if (typeFolders.isEmpty()) {
            typeFolder = new Eligibility_Folder__c();
            typeFolder.Name                  = qualificationType;
            typeFolder.Lead__c               = leadId;
            typeFolder.Level__c              = '1';
            typeFolder.Folder_Type__c        = 'QualificationType';
            typeFolder.Qualification_Type__c = qualificationType;
            insert typeFolder;
        } else {
            typeFolder = typeFolders[0];
        }

        Eligibility_Folder__c degreeFolder = new Eligibility_Folder__c();
        degreeFolder.Name                  = degreeTitle;
        degreeFolder.Lead__c               = leadId;
        degreeFolder.Level__c              = '2';
        degreeFolder.Folder_Type__c        = 'Degree';
        degreeFolder.Qualification_Type__c = qualificationType;
        degreeFolder.Degree_Title__c       = degreeTitle;
        degreeFolder.Parent_Folder__c      = typeFolder.Id;
        degreeFolder.Status__c             = 'Pending Review';
        insert degreeFolder;

        Eligibility_Folder__c certFolder = new Eligibility_Folder__c();
        certFolder.Name                  = 'Certificates';
        certFolder.Lead__c               = leadId;
        certFolder.Level__c              = '3';
        certFolder.Folder_Type__c        = 'Certificates';
        certFolder.Qualification_Type__c = qualificationType;
        certFolder.Degree_Title__c       = degreeTitle;
        certFolder.Parent_Folder__c      = degreeFolder.Id;

        Eligibility_Folder__c markFolder = new Eligibility_Folder__c();
        markFolder.Name                  = 'Marksheets';
        markFolder.Lead__c               = leadId;
        markFolder.Level__c              = '3';
        markFolder.Folder_Type__c        = 'Marksheets';
        markFolder.Qualification_Type__c = qualificationType;
        markFolder.Degree_Title__c       = degreeTitle;
        markFolder.Parent_Folder__c      = degreeFolder.Id;

        insert new List<Eligibility_Folder__c>{ certFolder, markFolder };

        return degreeFolder;
    }

    public static void setAllFoldersToPendingReviewForLead(Id leadId) {
        if (leadId == null) return;
        List<Eligibility_Folder__c> folders = [
            SELECT Id, Status__c
            FROM Eligibility_Folder__c
            WHERE Lead__c = :leadId
        ];
        if (folders.isEmpty()) return;

        List<Eligibility_Folder__c> updates = new List<Eligibility_Folder__c>();
        for (Eligibility_Folder__c f : folders) {
            if (f.Status__c != 'Pending Review') {
                updates.add(new Eligibility_Folder__c(
                    Id = f.Id,
                    Status__c = 'Pending Review'
                ));
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    // -------------- STATUS PROPAGATION --------------

    public static void recalcFromFileFolders(Set<Id> fileFolderIds) {
        if (fileFolderIds == null || fileFolderIds.isEmpty()) return;

        List<Eligibility_File__c> files = [
            SELECT Id, Folder__c, Lead__c, Status__c
            FROM Eligibility_File__c
            WHERE Folder__c IN :fileFolderIds
        ];

        Map<Id, List<Eligibility_File__c>> filesByFolder = new Map<Id, List<Eligibility_File__c>>();
        Set<Id> leadIds = new Set<Id>();
        for (Eligibility_File__c f : files) {
            if (!filesByFolder.containsKey(f.Folder__c)) {
                filesByFolder.put(f.Folder__c, new List<Eligibility_File__c>());
            }
            filesByFolder.get(f.Folder__c).add(f);
            leadIds.add(f.Lead__c);
        }

        List<Eligibility_Folder__c> folders = [
            SELECT Id, Lead__c, Status__c, Parent_Folder__c
            FROM Eligibility_Folder__c
            WHERE Id IN :fileFolderIds
        ];

        Map<Id, Lead__c> leads = new Map<Id, Lead__c>();
        if (!leadIds.isEmpty()) {
            for (Lead__c l : [
                SELECT Id, OwnerId, GP_Lead_Status__c
                FROM Lead__c
                WHERE Id IN :leadIds
            ]) {
                leads.put(l.Id, l);
            }
        }

        List<Eligibility_Folder__c> folderUpdates = new List<Eligibility_Folder__c>();
        List<Task> tasks = new List<Task>();
        Set<Id> parentIds = new Set<Id>();

        for (Eligibility_Folder__c folder : folders) {
            List<Eligibility_File__c> childFiles =
                filesByFolder.containsKey(folder.Id) ? filesByFolder.get(folder.Id) : new List<Eligibility_File__c>();

            String newStatus = calcStatusFromFiles(childFiles);
            if (String.isBlank(newStatus)) newStatus = 'Pending Review';

            if (folder.Status__c != newStatus) {
                folderUpdates.add(new Eligibility_Folder__c(
                    Id = folder.Id,
                    Status__c = newStatus
                ));

                if (newStatus != 'All Good') {
                    Lead__c leadRec = leads.get(folder.Lead__c);
                    if (leadRec != null && leadRec.OwnerId != null) {
                        Task t = new Task();
                        t.OwnerId  = leadRec.OwnerId;
                        t.WhatId   = leadRec.Id;
                        t.Subject  = 'Eligibility folder requires attention';
                        t.Status   = 'Not Started';
                        t.Priority = 'High';
                        tasks.add(t);
                    }
                }
            }

            if (folder.Parent_Folder__c != null) {
                parentIds.add(folder.Parent_Folder__c);
            }
        }

        if (!folderUpdates.isEmpty()) update folderUpdates;
        if (!tasks.isEmpty()) insert tasks;

        if (!parentIds.isEmpty()) {
            recalcFolderHierarchy(parentIds);
        }

        if (!leadIds.isEmpty()) {
            updateLeadStatusForLeads(leadIds);
        }
    }

    public static void recalcFromFiles(Set<Id> fileIds) {
        if (fileIds == null || fileIds.isEmpty()) return;

        List<Eligibility_File__c> files = [
            SELECT Id, Folder__c
            FROM Eligibility_File__c
            WHERE Id IN :fileIds
              AND Folder__c != null
        ];

        Set<Id> folderIds = new Set<Id>();
        for (Eligibility_File__c f : files) {
            folderIds.add(f.Folder__c);
        }

        recalcFromFileFolders(folderIds);
    }

    public static void recalcDegreeStatusByFile(Set<Id> fileIds) {
        recalcFromFiles(fileIds);
    }

    // -------------- PRIVATE STATUS HELPERS --------------

    private static String calcStatusFromFiles(List<Eligibility_File__c> files) {
        if (files == null || files.isEmpty()) {
            return 'Pending Review';
        }

        Boolean allVerified = true;
        Boolean anyRecheckOrReuploadRequired = false;
        Boolean anyReuploaded = false;
        Boolean allSubmittedOrReuploaded = true;

        for (Eligibility_File__c f : files) {
            String s = f.Status__c;
            if (s == 'Recheck' || s == 'Reupload_Required') {
                anyRecheckOrReuploadRequired = true;
            }
            if (s == 'Re-uploaded') {
                anyReuploaded = true;
            }
            if (s != 'Verified') {
                allVerified = false;
            }
            if (s != 'Submitted' && s != 'Re-uploaded') {
                allSubmittedOrReuploaded = false;
            }
        }

        if (allVerified) {
            return 'All Good';
        } else if (anyRecheckOrReuploadRequired) {
            return 'Recheck';
        } else if (anyReuploaded || allSubmittedOrReuploaded) {
            return 'Pending Review';
        } else {
            return 'Pending Review';
        }
    }

    private static void recalcFolderHierarchy(Set<Id> startingFolderIds) {
        if (startingFolderIds == null || startingFolderIds.isEmpty()) return;
    
        Set<Id> current = new Set<Id>(startingFolderIds);
    
        while (!current.isEmpty()) {
            List<Eligibility_Folder__c> childFolders = [
                SELECT Id, Status__c, Parent_Folder__c
                FROM Eligibility_Folder__c
                WHERE Parent_Folder__c IN :current
            ];
    
            if (childFolders.isEmpty()) {
                break;
            }
    
            Map<Id, List<Eligibility_Folder__c>> byParent = new Map<Id, List<Eligibility_Folder__c>>();
            for (Eligibility_Folder__c ch : childFolders) {
                if (!byParent.containsKey(ch.Parent_Folder__c)) {
                    byParent.put(ch.Parent_Folder__c, new List<Eligibility_Folder__c>());
                }
                byParent.get(ch.Parent_Folder__c).add(ch);
            }
    
            List<Eligibility_Folder__c> parents = [
                SELECT Id, Status__c, Parent_Folder__c
                FROM Eligibility_Folder__c
                WHERE Id IN :current
            ];
    
            List<Eligibility_Folder__c> updates = new List<Eligibility_Folder__c>();
            Set<Id> next = new Set<Id>();
    
            for (Eligibility_Folder__c parent : parents) {
                List<Eligibility_Folder__c> chList =
                    byParent.containsKey(parent.Id) ? byParent.get(parent.Id) : new List<Eligibility_Folder__c>();
    
                if (chList.isEmpty()) {
                    continue;
                }
    
                Boolean allAllGood = true;
                Boolean anyRecheck = false;
                Boolean allPending = true;
    
                for (Eligibility_Folder__c ch : chList) {
                    if (ch.Status__c != 'All Good') {
                        allAllGood = false;
                    }
                    if (ch.Status__c == 'Recheck') {
                        anyRecheck = true;
                    }
                    if (ch.Status__c != 'Pending Review') {
                        allPending = false;
                    }
                }
    
                String newStatus;
                if (allAllGood) {
                    newStatus = 'All Good';
                } else if (anyRecheck) {
                    newStatus = 'Recheck';
                } else if (allPending) {
                    newStatus = 'Pending Review';
                } else {
                    newStatus = 'Pending Review';
                }
    
                if (parent.Status__c != newStatus) {
                    updates.add(new Eligibility_Folder__c(
                        Id = parent.Id,
                        Status__c = newStatus
                    ));
                    if (parent.Parent_Folder__c != null) {
                        next.add(parent.Parent_Folder__c);
                    }
                }
            }
    
            if (!updates.isEmpty()) {
                update updates;
            }
    
            current = next;
        }
    }
    
    // -------------- UPDATE GP_LEAD_STATUS__c --------------

   // -------------- UPDATE GP_LEAD_STATUS__c --------------
private static void updateLeadStatusForLeads(Set<Id> leadIds) {
    if (leadIds == null || leadIds.isEmpty()) return;

    // Consider only NON-PARENT folders (i.e., folders which themselves have a parent)
    List<Eligibility_Folder__c> allFolders = [
        SELECT Id, Lead__c, Status__c, Parent_Folder__c
        FROM Eligibility_Folder__c
        WHERE Lead__c IN :leadIds
          AND Parent_Folder__c != null
    ];

    Map<Id, List<Eligibility_Folder__c>> foldersByLead = new Map<Id, List<Eligibility_Folder__c>>();
    for (Eligibility_Folder__c f : allFolders) {
        if (!foldersByLead.containsKey(f.Lead__c)) {
            foldersByLead.put(f.Lead__c, new List<Eligibility_Folder__c>());
        }
        foldersByLead.get(f.Lead__c).add(f);
    }

    Map<Id, Lead__c> leads = new Map<Id, Lead__c>();
    for (Lead__c l : [
        SELECT Id, GP_Lead_Status__c
        FROM Lead__c
        WHERE Id IN :leadIds
    ]) {
        leads.put(l.Id, l);
    }

    List<Lead__c> updates = new List<Lead__c>();

    for (Id lId : leadIds) {
        Lead__c existing = leads.get(lId);
        if (existing == null) continue;

        List<Eligibility_Folder__c> lf = foldersByLead.containsKey(lId)
            ? foldersByLead.get(lId)
            : new List<Eligibility_Folder__c>();

        if (lf.isEmpty()) {
            // No non-parent folders → do not change status
            continue;
        }

        Boolean allPending  = true;
        Boolean anyRecheck  = false;
        Boolean allAllGood  = true;

        for (Eligibility_Folder__c f : lf) {
            String s = f.Status__c;

            if (s == 'Recheck') {
                anyRecheck = true;
            }
            if (s != 'Pending Review') {
                allPending = false;
            }
            if (s != 'All Good') {
                allAllGood = false;
            }
        }

        String newStatus;
        // priority: Recheck > Verified > New lead > Verification
        if (anyRecheck) {
            newStatus = 'Recheck';
        } else if (allAllGood) {
            newStatus = 'Verified';
        } else if (allPending) {
            newStatus = 'New lead';
        } else {
            newStatus = 'Verification';
        }

        if (existing.GP_Lead_Status__c != newStatus) {
            updates.add(new Lead__c(
                Id = existing.Id,
                GP_Lead_Status__c = newStatus
            ));
        }
    }

    if (!updates.isEmpty()) {
        update updates;
    }
}


    // -------------- ELIGIBILITY CODE GENERATION --------------

    private static void generateEligibilityCodeForLead(Id leadId) {
        if (leadId == null) return;

        Lead__c l = [
            SELECT Id, City__c, Eligibility_Code__c, CreatedDate
            FROM Lead__c
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
            FROM Lead__c
            WHERE Eligibility_Code__c != null
              AND CreatedDate = TODAY
        ];

        Integer seq = countToday + 1;
        String seqStr = String.valueOf(seq);

        String code = 'Eligibility/' +
                      cityCode + '/' +
                      String.valueOf(today.day()) + '/' +
                      String.valueOf(today.month()) + '/' +
                      seqStr;

        l.Eligibility_Code__c = code;
        update l;
    }
}