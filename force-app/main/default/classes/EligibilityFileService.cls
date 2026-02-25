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
        public String salesforceId;           // UUID__c (Candidate/Student)
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
            res.message = 'Missing UUID (salesforceId).';
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

        EligibilityRecordResolver.Context ctx = EligibilityRecordResolver.resolveByKey(input.salesforceId);
        if (ctx == null || (ctx.studentId == null && ctx.candidateId == null)) {
            res.message = 'No Candidate or Student found for provided UUID.';
            return res;
        }
        Id candidateId = ctx.candidateId;
        Id studentId = ctx.studentId;

        // Find or create the degree folder and its child folders (Certificates/Marksheets)
        Eligibility_Folder__c degreeFolder =
            EligibilityFolderService.findDegreeFolderForContext(
                candidateId,
                studentId,
                input.qualificationType,
                input.qualificationTitle,
                input.qualificationMonthYear
            );
        if (degreeFolder == null) {
            degreeFolder = EligibilityFolderService.createDynamicDegreeFolders(
                candidateId,
                studentId,
                input.qualificationType,
                input.qualificationTitle
            );
        }
        EligibilityFolderService.ensureFolderLookups(degreeFolder, candidateId, studentId);

        Eligibility_Folder__c certFolder =
            EligibilityFolderService.findCategoryFolderForDoc(
                candidateId,
                studentId,
                input.qualificationType,
                input.qualificationTitle,
                'Certificate'
            );

        Eligibility_Folder__c markFolder =
            EligibilityFolderService.findCategoryFolderForDoc(
                candidateId,
                studentId,
                input.qualificationType,
                input.qualificationTitle,
                'Marksheet'
            );
        EligibilityFolderService.ensureFolderLookups(certFolder, candidateId, studentId);
        EligibilityFolderService.ensureFolderLookups(markFolder, candidateId, studentId);

        List<Eligibility_File__c> toUpsert = new List<Eligibility_File__c>();
        List<Eligibility_File__c> toDelete = new List<Eligibility_File__c>();
        Set<Id> affectedFolderIds = new Set<Id>();

        if (certFolder != null) {
            syncFilesForFolder(
                candidateId,
                studentId,
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
                candidateId,
                studentId,
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

        // Create "Upload document" Tasks for Student/GP user or Candidate
        createUploadDocTasks(candidateId, studentId, input);

        res.success = true;
        res.message = 'Qualification files synced successfully.';
        return res;
    }

    public static SimpleResponse handleMainFolderFiles(
        String salesforceId,
        String flatFolderKey,
        List<IncomingFile> incoming
    ) {
        SimpleResponse res = new SimpleResponse();
        res.success = false;
        res.message = 'Unknown error';

        if (String.isBlank(salesforceId)) {
            res.message = 'Missing UUID (salesforceId).';
            return res;
        }

        String key = EligibilityPathParser.normalizeFlatFolderKey(flatFolderKey);
        if (String.isBlank(key)) {
            res.message = 'Invalid main folder type.';
            return res;
        }

        EligibilityRecordResolver.Context ctx = EligibilityRecordResolver.resolveByKey(salesforceId);
        if (ctx == null || (ctx.studentId == null && ctx.candidateId == null)) {
            res.message = 'No Candidate or Student found for provided UUID.';
            return res;
        }
        Id candidateId = ctx.candidateId;
        Id studentId = ctx.studentId;

        String label = EligibilityPathParser.flatFolderLabel(key);
        Eligibility_Folder__c mainFolder =
            EligibilityFolderService.findMainFolderForFlatType(candidateId, studentId, key, label);
        if (mainFolder == null) {
            res.message = 'Main folder not found for ' + (label != null ? label : key) + '.';
            return res;
        }
        EligibilityFolderService.ensureFolderLookups(mainFolder, candidateId, studentId);

        List<Eligibility_File__c> toUpsert = new List<Eligibility_File__c>();
        List<Eligibility_File__c> toDelete = new List<Eligibility_File__c>();
        Set<Id> affectedFolderIds = new Set<Id>();

        String logicalType = String.isNotBlank(label) ? label : key;
        syncFilesForFolder(
            candidateId,
            studentId,
            mainFolder.Id,
            logicalType,
            incoming,
            toUpsert,
            toDelete,
            affectedFolderIds
        );

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }

        if (!affectedFolderIds.isEmpty()) {
            EligibilityFolderService.recalcFromFileFolders(affectedFolderIds);
        }

        NewQualificationRequest req = new NewQualificationRequest();
        req.qualificationTitle = logicalType;
        req.qualificationType = logicalType;
        req.qualificationMonthYear = null;
        createUploadDocTasks(candidateId, studentId, req);

        res.success = true;
        res.message = 'Main folder files synced successfully.';
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
        Id candidateId,
        Id studentId,
        Id folderId,
        String logicalFileType, // "Certificate" / "Marksheet"
        List<IncomingFile> incoming,
        List<Eligibility_File__c> toUpsert,
        List<Eligibility_File__c> toDelete,
        Set<Id> affectedFolderIds
    ) {
        if (incoming == null) incoming = new List<IncomingFile>();

        List<Eligibility_File__c> existing;
        if (studentId != null && candidateId != null) {
            existing = [
                SELECT Id, Candidate__c, Student__c, Folder__c, File_UUID__c, Status__c,
                       Storage_Key__c, File_Format__c, File_Type__c
                FROM Eligibility_File__c
                WHERE Folder__c = :folderId
                  AND (Student__c = :studentId OR Candidate__c = :candidateId)
            ];
        } else if (studentId != null) {
            existing = [
                SELECT Id, Candidate__c, Student__c, Folder__c, File_UUID__c, Status__c,
                       Storage_Key__c, File_Format__c, File_Type__c
                FROM Eligibility_File__c
                WHERE Folder__c = :folderId
                  AND Student__c = :studentId
            ];
        } else {
            existing = [
                SELECT Id, Candidate__c, Student__c, Folder__c, File_UUID__c, Status__c,
                       Storage_Key__c, File_Format__c, File_Type__c
                FROM Eligibility_File__c
                WHERE Folder__c = :folderId
                  AND Candidate__c = :candidateId
            ];
        }

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
                    File_Type__c = logicalFileType,
                    Status__c = 'Submitted'
                );
                if (candidateId != null) {
                    upd.Candidate__c = candidateId;
                }
                if (studentId != null) {
                    upd.Student__c = studentId;
                }
                toUpsert.add(upd);
            } else {
                Eligibility_File__c nf = new Eligibility_File__c();
                if (candidateId != null) {
                    nf.Candidate__c = candidateId;
                }
                if (studentId != null) {
                    nf.Student__c = studentId;
                }
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

    private static void createUploadDocTasks(Id candidateId, Id studentId, NewQualificationRequest req) {
        if (req == null || (candidateId == null && studentId == null)) {
            return;
        }

        List<Task> tasks = new List<Task>();

        if (studentId != null) {
            Account a = [
                SELECT Id, OwnerId, GP_User__c
                FROM Account
                WHERE Id = :studentId
                LIMIT 1
            ];

            Id gpUserId = a.GP_User__c;
            if (gpUserId == null && candidateId != null) {
                Lead l = [
                    SELECT GP_User__c
                    FROM Lead
                    WHERE Id = :candidateId
                    LIMIT 1
                ];
                gpUserId = l.GP_User__c;
            }

            if (a.OwnerId != null) {
                tasks.add(buildUploadTask(a.OwnerId, null, a.Id, req));
            }
            if (gpUserId != null && gpUserId != a.OwnerId) {
                tasks.add(buildUploadTask(gpUserId, null, a.Id, req));
            }
        } else if (candidateId != null) {
            Lead l = [
                SELECT Id, OwnerId, GP_User__c
                FROM Lead
                WHERE Id = :candidateId
                LIMIT 1
            ];
            Id ownerForTask = (l.GP_User__c != null) ? l.GP_User__c : l.OwnerId;
            if (ownerForTask != null) {
                tasks.add(buildUploadTask(ownerForTask, l.Id, null, req));
            }
        }

        if (!tasks.isEmpty()) {
            insert tasks;
        }
    }

    private static Task buildUploadTask(Id ownerId, Id whoId, Id whatId, NewQualificationRequest req) {
        Task t = new Task();
        t.OwnerId  = ownerId;
        if (whoId != null) {
            t.WhoId = whoId;
        }
        if (whatId != null) {
            t.WhatId = whatId;
        }
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
        return t;
    }
}