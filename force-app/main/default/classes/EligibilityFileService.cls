// file: force-app/main/default/classes/EligibilityFileService.cls
public without sharing class EligibilityFileService {

    public class IncomingFile {
        public String uuid;
        public String path;
        public String format;
        public String fileType; // "Certificate" / "Marksheet"
        public String fileName;
    }

    public class NewQualificationRequest {
        public String salesforceId;           // Lead.Id
        public String qualificationType;      // UG / PG / Certification
        public String qualificationTitle;     // B.Com, CA-Inter
        public String qualificationMonthYear; // e.g. "June 2024"
        public List<IncomingFile> certificateFiles;
        public List<IncomingFile> marksheetFiles;
    }

    public class SimpleResponse {
        public Boolean success;
        public String message;
    }

    @AuraEnabled
    public static SimpleResponse handleNewQualification(String inputJson) {
        SimpleResponse res = new SimpleResponse();
        res.success = false;
        res.message = 'Unknown error';

        if (String.isBlank(inputJson)) {
            res.message = 'Empty payload';
            return res;
        }

        NewQualificationRequest input;
        try {
            input = (NewQualificationRequest) JSON.deserialize(inputJson, NewQualificationRequest.class);
        } catch (Exception e) {
            res.message = 'Invalid payload: ' + e.getMessage();
            return res;
        }

        if (input == null || String.isBlank(input.salesforceId)) {
            res.message = 'Missing Lead Id (salesforceId).';
            return res;
        }

        // Derive qualification info from first file path if not provided
        if ((String.isBlank(input.qualificationType) || String.isBlank(input.qualificationTitle))
            && input.certificateFiles != null && !input.certificateFiles.isEmpty()) {
            EligibilityPathParser.ParsedPath p = EligibilityPathParser.parse(input.certificateFiles[0].path);
            if (p != null) {
                if (String.isBlank(input.qualificationType)) input.qualificationType = p.qualificationType;
                if (String.isBlank(input.qualificationTitle)) input.qualificationTitle = p.qualificationTitle;
            }
        }
        if ((String.isBlank(input.qualificationType) || String.isBlank(input.qualificationTitle))
            && input.marksheetFiles != null && !input.marksheetFiles.isEmpty()) {
            EligibilityPathParser.ParsedPath p = EligibilityPathParser.parse(input.marksheetFiles[0].path);
            if (p != null) {
                if (String.isBlank(input.qualificationType)) input.qualificationType = p.qualificationType;
                if (String.isBlank(input.qualificationTitle)) input.qualificationTitle = p.qualificationTitle;
            }
        }

        if (String.isBlank(input.qualificationType) || String.isBlank(input.qualificationTitle)) {
            res.message = 'Missing qualification type/title.';
            return res;
        }

        Id leadId = Id.valueOf(input.salesforceId);

        // Find or create the degree folder and its child folders (Certificates/Marksheets)
        Eligibility_Folder__c degreeFolder =
            EligibilityFolderService.findDegreeFolder(
                leadId,
                input.qualificationType,
                input.qualificationTitle,
                input.qualificationMonthYear
            );
        if (degreeFolder == null) {
            degreeFolder = EligibilityFolderService.createDynamicDegreeFolders(
                leadId,
                input.qualificationType,
                input.qualificationTitle
            );
        }

        Eligibility_Folder__c certFolder =
            EligibilityFolderService.findCategoryFolderForDoc(
                leadId,
                input.qualificationType,
                input.qualificationTitle,
                'Certificate'
            );

        Eligibility_Folder__c markFolder =
            EligibilityFolderService.findCategoryFolderForDoc(
                leadId,
                input.qualificationType,
                input.qualificationTitle,
                'Marksheet'
            );

        List<Eligibility_File__c> toUpsert = new List<Eligibility_File__c>();
        List<Eligibility_File__c> toDelete = new List<Eligibility_File__c>();
        Set<Id> affectedFolderIds = new Set<Id>();

        if (certFolder != null) {
            syncFilesForFolder(
                leadId,
                certFolder.Id,
                'Certificate',
                input.certificateFiles,
                toUpsert,
                toDelete,
                affectedFolderIds
            );
        }

        if (markFolder != null) {
            syncFilesForFolder(
                leadId,
                markFolder.Id,
                'Marksheet',
                input.marksheetFiles,
                toUpsert,
                toDelete,
                affectedFolderIds
            );
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }

        if (!affectedFolderIds.isEmpty()) {
            EligibilityFolderService.recalcFromFileFolders(affectedFolderIds);
        }

        // Create "Upload document" Task for GP user on Lead
        createUploadDocTaskForLead(leadId, input);

        res.success = true;
        res.message = 'Qualification files synced successfully.';
        return res;
    }

    // Extracts the file name from a full path (supports "/" and "\" separators).
    private static String extractFileName(String filePath) {
        if (String.isBlank(filePath)) {
            return null;
        }
        List<String> parts = filePath.split('[\\\\/]');
        if (parts.isEmpty()) {
            return null;
        }
        return parts.get(parts.size() - 1);
    }

    private static void syncFilesForFolder(
        Id leadId,
        Id folderId,
        String logicalFileType, // "Certificate" / "Marksheet"
        List<IncomingFile> incoming,
        List<Eligibility_File__c> toUpsert,
        List<Eligibility_File__c> toDelete,
        Set<Id> affectedFolderIds
    ) {
        if (incoming == null) incoming = new List<IncomingFile>();

        List<Eligibility_File__c> existing = [
            SELECT Id, Candidate__c, Folder__c, File_UUID__c, Status__c,
                   Storage_Key__c, File_Format__c, File_Type__c
            FROM Eligibility_File__c
            WHERE Candidate__c = :leadId
              AND Folder__c = :folderId
        ];

        Map<String, Eligibility_File__c> existingByUuid = new Map<String, Eligibility_File__c>();
        Set<String> existingUuids = new Set<String>();

        for (Eligibility_File__c ef : existing) {
            if (!String.isBlank(ef.File_UUID__c)) {
                existingByUuid.put(ef.File_UUID__c, ef);
                existingUuids.add(ef.File_UUID__c);
            }
        }

        Set<String> incomingUuids = new Set<String>();
        for (IncomingFile inf : incoming) {
            if (String.isBlank(inf.uuid)) continue;
            incomingUuids.add(inf.uuid);

            Eligibility_File__c existingFile = existingByUuid.get(inf.uuid);
            String fileName = !String.isBlank(inf.fileName) ? inf.fileName : extractFileName(inf.path);

            if (existingFile != null) {
                Eligibility_File__c upd = new Eligibility_File__c(
                    Id = existingFile.Id,
                    Name = fileName,
                    Storage_Key__c = inf.path,
                    File_Format__c = inf.format,
                    File_Type__c = logicalFileType
                );
                toUpsert.add(upd);
            } else {
                Eligibility_File__c nf = new Eligibility_File__c();
                nf.Candidate__c = leadId;
                nf.Folder__c = folderId;
                nf.Name = fileName;
                nf.File_UUID__c = inf.uuid;
                nf.Storage_Key__c = inf.path;
                nf.File_Format__c = inf.format;
                nf.File_Type__c = logicalFileType;
                nf.Status__c = 'Submitted';
                toUpsert.add(nf);
            }
        }

        for (Eligibility_File__c ef : existing) {
            if (!String.isBlank(ef.File_UUID__c) && !incomingUuids.contains(ef.File_UUID__c)) {
                toDelete.add(ef);
            }
        }

        if (!incoming.isEmpty() || !existing.isEmpty()) {
            affectedFolderIds.add(folderId);
        }
    }

    private static void createUploadDocTaskForLead(Id leadId, NewQualificationRequest req) {
        if (leadId == null || req == null) {
            return;
        }

        Lead l = [
            SELECT Id, OwnerId, GP_User__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];

        Id ownerForTask = (l.GP_User__c != null) ? l.GP_User__c : l.OwnerId;
        if (ownerForTask == null) {
            return;
        }

        Task t = new Task();
        t.OwnerId  = ownerForTask;
        t.WhoId    = l.Id;
        t.Subject  = 'Upload eligibility documents - ' +
                     (String.isNotBlank(req.qualificationTitle)
                        ? req.qualificationTitle
                        : req.qualificationType);
        t.Status   = 'Not Started';
        t.Priority = 'High';
        t.ActivityDate = System.today();

        String bodyText = 'Documents have been shared via API for eligibility review.';
        bodyText += '\n\nQualification Type: ';
        if (req.qualificationType != null) {
            bodyText += req.qualificationType;
        }
        bodyText += '\nQualification Title: ';
        if (req.qualificationTitle != null) {
            bodyText += req.qualificationTitle;
        }
        bodyText += '\nMonth / Year: ';
        if (req.qualificationMonthYear != null) {
            bodyText += req.qualificationMonthYear;
        }

        t.Description = bodyText;

        insert t;
    }
}