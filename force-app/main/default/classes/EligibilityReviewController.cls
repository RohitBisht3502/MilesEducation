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
        @AuraEnabled public String yearOfGraduation; // String for LWC combobox
        @AuraEnabled public String grade;
        @AuraEnabled public String rankDivision;
        @AuraEnabled public String university;
        @AuraEnabled public Integer courseDuration;
        @AuraEnabled public String graduationType;
        @AuraEnabled public String degreeStatus;
        @AuraEnabled public String comment;      // NEW: file-level comment
    }

    public class FolderNode {
        @AuraEnabled public Id    id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String folderType;
        @AuraEnabled public String qualificationType;
        @AuraEnabled public String degreeTitle;
        @AuraEnabled public String level;
        @AuraEnabled public String monthYear;
        @AuraEnabled public String comments;
        @AuraEnabled public List<FolderNode> children;
        @AuraEnabled public List<FileNode> files;
    }

    public class FileUpdateInput {
        @AuraEnabled public Id fileId;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal percentage;
        @AuraEnabled public String yearOfGraduation;
        @AuraEnabled public String grade;
        @AuraEnabled public String rankDivision;
        @AuraEnabled public String university;
        @AuraEnabled public Integer courseDuration;
        @AuraEnabled public String graduationType;
        @AuraEnabled public String degreeStatus;
        @AuraEnabled public String comment;
    }

    public class SimpleResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }

    public class PicklistResponse {
        @AuraEnabled public List<String> universityValues;
        @AuraEnabled public List<String> gradeValues;
        @AuraEnabled public List<String> rankValues;
    }

    // ----------- GET TREE -----------

    @AuraEnabled(cacheable=true)
    public static List<FolderNode> getFolderTree(Id leadId) {
        if (leadId == null) return new List<FolderNode>();

        List<Eligibility_Folder__c> folders = [
            SELECT Id, Name, Status__c, Folder_Type__c, Qualification_Type__c,
                   Degree_Title__c, Level__c, Month_Year__c, Parent_Folder__c,
                   Comments__c
            FROM Eligibility_Folder__c
            WHERE Lead__c = :leadId
            ORDER BY Level__c, Name
        ];

        List<Eligibility_File__c> files = [
            SELECT Id, Name, Status__c, File_Type__c, File_Format__c,
                   Storage_Key__c, Percentage__c, Year_of_Graduation__c,
                   Grade__c, Rank_Division__c, University__c, Course_Duration__c,
                   Graduation_Type__c, Degree_Status__c, Folder__c, Comment__c
            FROM Eligibility_File__c
            WHERE Lead__c = :leadId
        ];

        Map<Id, FolderNode> nodeById = new Map<Id, FolderNode>();
        Map<Id, List<FolderNode>> childrenByParent = new Map<Id, List<FolderNode>>();
        List<FolderNode> roots = new List<FolderNode>();

        for (Eligibility_Folder__c f : folders) {
            FolderNode n = new FolderNode();
            n.id                = f.Id;
            n.name              = f.Name;
            n.status            = f.Status__c;
            n.folderType        = f.Folder_Type__c;
            n.qualificationType = f.Qualification_Type__c;
            n.degreeTitle       = f.Degree_Title__c;
            n.level             = f.Level__c;
            n.monthYear         = f.Month_Year__c;
            n.comments          = f.Comments__c;
            n.children          = new List<FolderNode>();
            n.files             = new List<FileNode>();
            nodeById.put(f.Id, n);

            if (f.Parent_Folder__c == null) {
                roots.add(n);
            } else {
                if (!childrenByParent.containsKey(f.Parent_Folder__c)) {
                    childrenByParent.put(f.Parent_Folder__c, new List<FolderNode>());
                }
                childrenByParent.get(f.Parent_Folder__c).add(n);
            }
        }

        for (Id folderId : nodeById.keySet()) {
            FolderNode node = nodeById.get(folderId);
            if (childrenByParent.containsKey(folderId)) {
                node.children.addAll(childrenByParent.get(folderId));
            }
        }

        for (Eligibility_File__c f : files) {
            if (f.Folder__c == null) continue;
            FolderNode parent = nodeById.get(f.Folder__c);
            if (parent == null) continue;

            FileNode fn = new FileNode();
            fn.id               = f.Id;
            fn.name             = f.Name;
            fn.status           = f.Status__c;
            fn.fileType         = f.File_Type__c;
            fn.fileFormat       = f.File_Format__c;
            fn.storageKey       = f.Storage_Key__c;
            fn.percentage       = f.Percentage__c;
            fn.yearOfGraduation = (f.Year_of_Graduation__c == null ? null : String.valueOf(f.Year_of_Graduation__c));
            fn.grade            = f.Grade__c;
            fn.rankDivision     = f.Rank_Division__c;
            fn.university       = f.University__c;
            fn.courseDuration   = (f.Course_Duration__c == null ? null : Integer.valueOf(f.Course_Duration__c));
            fn.graduationType   = f.Graduation_Type__c;
            fn.degreeStatus     = f.Degree_Status__c;
            fn.comment          = f.Comment__c;

            parent.files.add(fn);
        }

        return roots;
    }

    // ----------- SAVE FILE EDIT (STRING PAYLOAD) -----------

    @AuraEnabled
    public static SimpleResponse saveFile(String inputJson) {
        System.debug('EligibilityReviewController.saveFile raw inputJson: ' + inputJson);

        SimpleResponse res = new SimpleResponse();
        res.success = false;

        if (String.isBlank(inputJson)) {
            res.message = 'Empty inputJson.';
            return res;
        }

        FileUpdateInput input;
        try {
            input = (FileUpdateInput) JSON.deserialize(inputJson, FileUpdateInput.class);
        } catch (Exception ex) {
            res.message = 'Failed to parse inputJson: ' + ex.getMessage();
            return res;
        }

        System.debug('EligibilityReviewController.saveFile parsed input: ' + JSON.serialize(input));

        if (input == null || input.fileId == null) {
            res.message = 'Missing fileId.';
            System.debug('EligibilityReviewController.saveFile ERROR: input or fileId is null.');
            return res;
        }

        Eligibility_File__c file = [
            SELECT Id, Folder__c, Lead__c
            FROM Eligibility_File__c
            WHERE Id = :input.fileId
            LIMIT 1
        ];
        System.debug('EligibilityReviewController.saveFile loaded file Id: ' + file.Id);

        Eligibility_File__c upd = new Eligibility_File__c(Id = file.Id);
        if (input.status != null)           upd.Status__c             = input.status;
        if (input.percentage != null)       upd.Percentage__c         = input.percentage;

        if (input.yearOfGraduation != null) {
            try {
                upd.Year_of_Graduation__c = Integer.valueOf(input.yearOfGraduation);
            } catch (Exception e) {
                System.debug('Invalid yearOfGraduation value: ' + input.yearOfGraduation + ' -> ' + e.getMessage());
            }
        }

        if (input.grade != null)            upd.Grade__c              = input.grade;
        if (input.rankDivision != null)     upd.Rank_Division__c      = input.rankDivision;
        if (input.university != null)       upd.University__c         = input.university;
        if (input.comment != null)          upd.Comment__c            = input.comment;

        update upd;
        System.debug('EligibilityReviewController.saveFile: File updated.');

        // Recalculate folder statuses & update lead GP_Lead_Status__c internally
        EligibilityFolderService.recalcFromFileFolders(new Set<Id>{ file.Folder__c });

        res.success = true;
        res.message = 'File updated successfully.';
        return res;
    }

    // ----------- SAVE FOLDER COMMENT -----------

    @AuraEnabled
    public static SimpleResponse saveFolderComment(Id folderId, String comment) {
        SimpleResponse res = new SimpleResponse();
        res.success = false;

        if (folderId == null) {
            res.message = 'Missing folderId.';
            return res;
        }

        Eligibility_Folder__c folder = [
            SELECT Id, Lead__c, Comments__c, Lead__r.OwnerId
            FROM Eligibility_Folder__c
            WHERE Id = :folderId
            LIMIT 1
        ];

        Eligibility_Folder__c upd = new Eligibility_Folder__c(
            Id = folder.Id,
            Comments__c = comment
        );
        update upd;

        if (folder.Lead__c != null && folder.Lead__r.OwnerId != null) {
            Task t = new Task();
            t.OwnerId  = folder.Lead__r.OwnerId;
            t.WhatId   = folder.Lead__c;
            t.Subject  = 'Eligibility folder comment added';
            t.Status   = 'Not Started';
            t.Priority = 'High';
            insert t;
        }

        res.success = true;
        res.message = 'Comment saved successfully.';
        return res;
    }

    // ----------- PICKLIST VALUES FOR FILE FIELDS -----------

    @AuraEnabled(cacheable=true)
    public static PicklistResponse getFileFieldPicklists() {
        PicklistResponse resp = new PicklistResponse();
        resp.universityValues = new List<String>();
        resp.gradeValues      = new List<String>();
        resp.rankValues       = new List<String>();

        Schema.DescribeSObjectResult sobj = Eligibility_File__c.SObjectType.getDescribe();
        Map<String, Schema.SObjectField> fields = sobj.fields.getMap();

        if (fields.containsKey('University__c')) {
            Schema.DescribeFieldResult df = fields.get('University__c').getDescribe();
            for (Schema.PicklistEntry pe : df.getPicklistValues()) {
                if (!pe.isActive()) continue;
                resp.universityValues.add(pe.getValue());
            }
        }

        if (fields.containsKey('Grade__c')) {
            Schema.DescribeFieldResult df = fields.get('Grade__c').getDescribe();
            for (Schema.PicklistEntry pe : df.getPicklistValues()) {
                if (!pe.isActive()) continue;
                resp.gradeValues.add(pe.getValue());
            }
        }

        if (fields.containsKey('Rank_Division__c')) {
            Schema.DescribeFieldResult df = fields.get('Rank_Division__c').getDescribe();
            for (Schema.PicklistEntry pe : df.getPicklistValues()) {
                if (!pe.isActive()) continue;
                resp.rankValues.add(pe.getValue());
            }
        }

        return resp;
    }

    // ----------- GP LEAD STATUS FOR PATH -----------

    @AuraEnabled(cacheable=true)
    public static String getLeadEligibilityStatus(Id leadId) {
        if (leadId == null) return 'New lead';

        Lead__c l = [
            SELECT Id, GP_Lead_Status__c
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];

        if (String.isBlank(l.GP_Lead_Status__c)) {
            return 'New lead';
        }
        return l.GP_Lead_Status__c;
    }
}