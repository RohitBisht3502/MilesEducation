// file: force-app/main/default/classes/EligibilityReviewController.cls
public without sharing class EligibilityReviewController {

    // ----------- DTOs for LWC -----------

    public class FileNode {
        @AuraEnabled public Id    id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String fileType;     // Certificate / Marksheet
        @AuraEnabled public String fileFormat;   // pdf / jpg ...
        @AuraEnabled public String storageKey;   // URL/path
        @AuraEnabled public Decimal percentage;
        @AuraEnabled public String yearOfGraduation;
        @AuraEnabled public String grade;
        @AuraEnabled public String rankDivision;
        @AuraEnabled public String university;
        @AuraEnabled public String comment;
        @AuraEnabled public String createdDate;
    }

    public class FolderNode {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String folderType;
        @AuraEnabled public String qualificationType;
        @AuraEnabled public String degreeTitle;
        @AuraEnabled public String monthYear;
        @AuraEnabled public String comments;
        @AuraEnabled public String createdDate;
        @AuraEnabled public List<FolderNode> children;
        @AuraEnabled public List<FileNode> files;
    }

    public class PicklistResponse {
        @AuraEnabled public List<String> universityValues;
        @AuraEnabled public List<String> gradeValues;
        @AuraEnabled public List<String> rankValues;
    }

    public class SimpleResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }

    private class FileInput {
        public Id fileId;
        public String status;
        public String comment;
    }

    // ----------- TREE API -----------

    @AuraEnabled(cacheable=true)
    public static List<FolderNode> getFolderTree(Id leadId) {
        if (leadId == null) return new List<FolderNode>();

        List<Eligibility_Folder__c> folders = [
            SELECT Id, Name, Status__c, Folder_Type__c, Qualification_Type__c,
                   Degree_Title__c, Level__c, Month_Year__c, Parent_Folder__c,
                   Comments__c, CreatedDate
            FROM Eligibility_Folder__c
            WHERE Candidate__c = :leadId
            ORDER BY Level__c, Name
        ];

        List<Eligibility_File__c> files = [
            SELECT Id, Name, Status__c, File_Type__c, File_Format__c, Storage_Key__c,
                   Percentage__c, Year_of_Graduation__c, Grade__c, Rank_Division__c,
                   University__c, Comment__c, Folder__c, CreatedDate
            FROM Eligibility_File__c
            WHERE Candidate__c = :leadId
        ];

        Map<Id, FolderNode> folderMap = new Map<Id, FolderNode>();
        for (Eligibility_Folder__c f : folders) {
            FolderNode fn = new FolderNode();
            fn.id = f.Id;
            fn.name = f.Name;
            fn.status = f.Status__c;
            fn.folderType = f.Folder_Type__c;
            fn.qualificationType = f.Qualification_Type__c;
            fn.degreeTitle = f.Degree_Title__c;
            fn.monthYear = f.Month_Year__c;
            fn.comments = f.Comments__c;
            fn.createdDate = (f.CreatedDate != null)
                ? String.valueOf(f.CreatedDate.date())
                : null;
            fn.children = new List<FolderNode>();
            fn.files = new List<FileNode>();
            folderMap.put(f.Id, fn);
        }

        // Attach children
        List<FolderNode> roots = new List<FolderNode>();
        for (Eligibility_Folder__c f : folders) {
            FolderNode node = folderMap.get(f.Id);
            if (f.Parent_Folder__c == null) {
                roots.add(node);
            } else if (folderMap.containsKey(f.Parent_Folder__c)) {
                folderMap.get(f.Parent_Folder__c).children.add(node);
            } else {
                roots.add(node);
            }
        }

        // Attach files
        for (Eligibility_File__c f : files) {
            if (f.Folder__c == null) continue;
            FolderNode parent = folderMap.get(f.Folder__c);
            if (parent == null) continue;

            FileNode fn = new FileNode();
            fn.id = f.Id;
            fn.name = f.Name;
            fn.status = f.Status__c;
            fn.fileType = f.File_Type__c;
            fn.fileFormat = f.File_Format__c;
            fn.storageKey = f.Storage_Key__c;
            fn.percentage = f.Percentage__c;
            fn.yearOfGraduation = (f.Year_of_Graduation__c != null)
                ? String.valueOf(f.Year_of_Graduation__c)
                : null;
            fn.grade = f.Grade__c;
            fn.rankDivision = f.Rank_Division__c;
            fn.university = f.University__c;
            fn.comment = f.Comment__c;
            fn.createdDate = (f.CreatedDate != null)
                ? String.valueOf(f.CreatedDate.date())
                : null;

            parent.files.add(fn);
        }

        return roots;
    }

    // ----------- LEAD STATUS -----------

    @AuraEnabled(cacheable=true)
    public static String getLeadEligibilityStatus(Id leadId) {
        if (leadId == null) return null;
        Lead l = [
            SELECT Id, GP_Lead_Status__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];
        return l.GP_Lead_Status__c;
    }

    // ----------- PICKLISTS FOR FILE FIELDS -----------

    @AuraEnabled(cacheable=true)
    public static PicklistResponse getFileFieldPicklists() {
        PicklistResponse res = new PicklistResponse();
        res.universityValues = new List<String>();
        res.gradeValues = new List<String>();
        res.rankValues = new List<String>();

        Schema.DescribeSObjectResult d = Eligibility_File__c.SObjectType.getDescribe();
        Map<String, Schema.SObjectField> fm = d.fields.getMap();

        if (fm.containsKey('University__c')) {
            Schema.DescribeFieldResult fr = fm.get('University__c').getDescribe();
            for (Schema.PicklistEntry pe : fr.getPicklistValues()) {
                res.universityValues.add(pe.getLabel());
            }
        }
        if (fm.containsKey('Grade__c')) {
            Schema.DescribeFieldResult fr = fm.get('Grade__c').getDescribe();
            for (Schema.PicklistEntry pe : fr.getPicklistValues()) {
                res.gradeValues.add(pe.getLabel());
            }
        }
        if (fm.containsKey('Rank_Division__c')) {
            Schema.DescribeFieldResult fr = fm.get('Rank_Division__c').getDescribe();
            for (Schema.PicklistEntry pe : fr.getPicklistValues()) {
                res.rankValues.add(pe.getLabel());
            }
        }

        return res;
    }

    // ----------- SAVE FILE EDIT -----------

    @AuraEnabled
    public static SimpleResponse saveFile(String inputJson) {
        SimpleResponse res = new SimpleResponse();
        res.success = false;
        res.message = 'Unknown error';

        if (String.isBlank(inputJson)) {
            res.message = 'Empty payload.';
            return res;
        }

        FileInput input;
        try {
            input = (FileInput) JSON.deserialize(inputJson, FileInput.class);
        } catch (Exception e) {
            res.message = 'Invalid JSON payload: ' + e.getMessage();
            return res;
        }

        if (input == null || input.fileId == null) {
            res.message = 'Missing fileId.';
            return res;
        }

        Eligibility_File__c file = [
            SELECT Id, Folder__c, Candidate__c, Name, Status__c, File_Type__c
            FROM Eligibility_File__c
            WHERE Id = :input.fileId
            LIMIT 1
        ];

        String oldStatus = file.Status__c;
        String newStatus = input.status;

        Eligibility_File__c upd = new Eligibility_File__c(
            Id = file.Id,
            Status__c = newStatus,
            Comment__c = input.comment
        );
        update upd;

        // Recalculate Lead status based on existing folder statuses (no folder auto-update)
        EligibilityFolderService.recalcFromFiles(new Set<Id>{ file.Id });

        // Task on file status change (except Verified)
        if (file.Candidate__c != null && oldStatus != newStatus && newStatus != 'Verified') {
            Lead l = [
                SELECT Id, OwnerId
                FROM Lead
                WHERE Id = :file.Candidate__c
                LIMIT 1
            ];
            if (l.OwnerId != null) {
                Task t = new Task();
                t.OwnerId = l.OwnerId;
                t.WhoId = l.Id;
                t.Subject = 'Eligibility file status updated - ' + (String.isNotBlank(file.Name) ? file.Name : 'Document');
                t.Status = 'Not Started';
                t.Priority = 'High';
                t.ActivityDate = System.today();
                t.Description =
                    'File "' + (String.isNotBlank(file.Name) ? file.Name : String.valueOf(file.Id)) +
                    '" (' + (file.File_Type__c != null ? file.File_Type__c : 'Eligibility Document') + ')' +
                    ' status changed from "' + (oldStatus != null ? oldStatus : 'None') +
                    '" to "' + (newStatus != null ? newStatus : 'None') + '".' +
                    (String.isNotBlank(input.comment) ? '\nReviewer comment: ' + input.comment : '');
                insert t;
            }
        }

        // Post to Datalake (async) except when Verified
        if (oldStatus != newStatus && newStatus != 'Verified') {
            try {
                EligibilityResponseService.sendForFile(file.Id);
            } catch (Exception e) {
                System.debug('EligibilityReviewController.saveFile callout failed: ' + e.getMessage());
            }
        }

        res.success = true;
        res.message = 'File updated successfully.';
        return res;
    }

    // ----------- FOLDER COMMENT / STATUS APIS -----------

    @AuraEnabled
    public static SimpleResponse saveFolderComment(Id folderId, String comment) {
        // Backwards compatible – just update comment, keep current status
        return updateFolderStatus(folderId, null, comment);
    }

    @AuraEnabled
    public static SimpleResponse updateFolderStatus(Id folderId, String status, String comment) {
        SimpleResponse res = new SimpleResponse();
        res.success = false;

        if (folderId == null) {
            res.message = 'Missing folderId.';
            return res;
        }

        Eligibility_Folder__c oldFolder = [
            SELECT Id, Candidate__c, Name, Status__c, Comments__c, Folder_Type__c
            FROM Eligibility_Folder__c
            WHERE Id = :folderId
            LIMIT 1
        ];

        if (oldFolder.Folder_Type__c != 'Degree') {
            res.message = 'Only degree folders can be updated.';
            return res;
        }

        String finalStatus = (status != null) ? status : oldFolder.Status__c;
        String finalComment = (comment != null) ? comment : oldFolder.Comments__c;

        Eligibility_Folder__c upd = new Eligibility_Folder__c(
            Id = folderId,
            Status__c = finalStatus,
            Comments__c = finalComment
        );
        update upd;

        // Build "new" snapshot for service
        Eligibility_Folder__c newFolder = new Eligibility_Folder__c(
            Id = oldFolder.Id,
            Candidate__c = oldFolder.Candidate__c,
            Name = oldFolder.Name,
            Status__c = finalStatus,
            Comments__c = finalComment
        );

        EligibilityFolderService.handleSingleFolderUpdate(oldFolder, newFolder);

        // Post to Datalake except for neutral statuses
        if (oldFolder.Status__c != finalStatus
            && finalStatus != 'All Good'
            && finalStatus != 'Pending Review') {
            try {
                EligibilityResponseService.sendForDegreeFolder(oldFolder.Id);
            } catch (Exception e) {
                System.debug('EligibilityReviewController.updateFolderStatus callout failed: ' + e.getMessage());
            }
        }

        res.success = true;
        res.message = 'Folder updated successfully.';
        return res;
    }

    @AuraEnabled
    public static String getDownloadUrl(Id fileId) {
        if (fileId == null) {
            throw new AuraHandledException('Missing fileId.');
        }
        Eligibility_File__c f = [
            SELECT Storage_Key__c
            FROM Eligibility_File__c
            WHERE Id = :fileId
            LIMIT 1
        ];
        if (String.isBlank(f.Storage_Key__c)) {
            throw new AuraHandledException('No file path found for this file.');
        }
        return EligibilityDatalakeClient.getDownloadUrl(f.Storage_Key__c);
    }
}