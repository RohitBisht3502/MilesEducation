// Builds and sends eligibility status updates to the datalake.
public without sharing class EligibilityResponseService {

    @future(callout=true)
    public static void sendForFile(Id fileId) {
        if (fileId == null) {
            logSkipped('sendForFile: missing fileId', null);
            return;
        }

        Eligibility_File__c file = [
            SELECT Id, Candidate__c, Student__c, Folder__c, File_UUID__c, Storage_Key__c, File_Format__c,
                   Status__c, Comment__c, Name, File_Type__c
            FROM Eligibility_File__c
            WHERE Id = :fileId
            LIMIT 1
        ];

        if ((file.Candidate__c == null && file.Student__c == null) || file.Folder__c == null) {
            logSkipped('sendForFile: missing candidate/student or folder', '{"fileId":"' + String.valueOf(fileId) + '"}');
            return;
        }

        Eligibility_Folder__c fileFolder = [
            SELECT Id, Name, Folder_Type__c, Parent_Folder__c, Qualification_Type__c, Degree_Title__c, Status__c, Comments__c,
                   Candidate__c, Student__c
            FROM Eligibility_Folder__c
            WHERE Id = :file.Folder__c
            LIMIT 1
        ];

        String flatKey = resolveFlatFolderKey(fileFolder);
        if (String.isNotBlank(flatKey)) {
            String uuid = resolveUuidForRecord(file.Student__c, file.Candidate__c);
            if (String.isBlank(uuid)) {
                logSkipped('sendForFile: missing uuid for flat folder', '{"fileId":"' + String.valueOf(fileId) + '"}');
                return;
            }
            sendFlatFolderPayload(fileFolder, uuid);
            return;
        }

        if (fileFolder.Parent_Folder__c == null) {
            logSkipped('sendForFile: missing parent degree folder', '{"fileId":"' + String.valueOf(fileId) + '"}');
            return;
        }

        Eligibility_Folder__c degreeFolder = [
            SELECT Id, Candidate__c, Student__c, Name, Degree_Title__c, Status__c, Comments__c
            FROM Eligibility_Folder__c
            WHERE Id = :fileFolder.Parent_Folder__c
            LIMIT 1
        ];
        if (degreeFolder == null) {
            logSkipped('sendForFile: degree folder not found', '{"fileId":"' + String.valueOf(fileId) + '"}');
            return;
        }

        String uuid = resolveUuidForRecord(degreeFolder.Student__c, degreeFolder.Candidate__c);
        if (String.isBlank(uuid)) {
            logSkipped('sendForFile: missing uuid for degree folder', '{"fileId":"' + String.valueOf(fileId) + '"}');
            return;
        }
        sendDegreeFolderPayload(degreeFolder, uuid);
    }

    @future(callout=true)
    public static void sendForDegreeFolder(Id folderId) {
        if (folderId == null) {
            logSkipped('sendForDegreeFolder: missing folderId', null);
            return;
        }

        Eligibility_Folder__c degreeFolder = [
            SELECT Id, Candidate__c, Student__c, Name, Degree_Title__c, Status__c, Comments__c
            FROM Eligibility_Folder__c
            WHERE Id = :folderId
            LIMIT 1
        ];
        if (degreeFolder.Candidate__c == null && degreeFolder.Student__c == null) {
            logSkipped('sendForDegreeFolder: missing candidate/student', '{"folderId":"' + String.valueOf(folderId) + '"}');
            return;
        }

        String uuid = resolveUuidForRecord(degreeFolder.Student__c, degreeFolder.Candidate__c);
        if (String.isBlank(uuid)) {
            logSkipped('sendForDegreeFolder: missing uuid', '{"folderId":"' + String.valueOf(folderId) + '"}');
            return;
        }
        sendDegreeFolderPayload(degreeFolder, uuid);
    }

    @future(callout=true)
    public static void sendForFlatFolder(Id folderId) {
        if (folderId == null) {
            logSkipped('sendForFlatFolder: missing folderId', null);
            return;
        }

        Eligibility_Folder__c flatFolder = [
            SELECT Id, Candidate__c, Student__c, Name, Folder_Type__c, Qualification_Type__c,
                   Degree_Title__c, Status__c, Comments__c
            FROM Eligibility_Folder__c
            WHERE Id = :folderId
            LIMIT 1
        ];
        if (flatFolder.Candidate__c == null && flatFolder.Student__c == null) {
            logSkipped('sendForFlatFolder: missing candidate/student', '{"folderId":"' + String.valueOf(folderId) + '"}');
            return;
        }

        String uuid = resolveUuidForRecord(flatFolder.Student__c, flatFolder.Candidate__c);
        if (String.isBlank(uuid)) {
            logSkipped('sendForFlatFolder: missing uuid', '{"folderId":"' + String.valueOf(folderId) + '"}');
            return;
        }
        sendFlatFolderPayload(flatFolder, uuid);
    }

    private static void sendDegreeFolderPayload(Eligibility_Folder__c degreeFolder, String uuid) {
        if (degreeFolder == null || String.isBlank(uuid)) {
            logSkipped('sendDegreeFolderPayload: missing folder/uuid', null);
            return;
        }

        Map<String, Id> categoryIds = new Map<String, Id>();
        for (Eligibility_Folder__c cf : [
            SELECT Id, Folder_Type__c
            FROM Eligibility_Folder__c
            WHERE Parent_Folder__c = :degreeFolder.Id
        ]) {
            categoryIds.put(cf.Folder_Type__c, cf.Id);
        }

        List<Eligibility_File__c> files;
        if (degreeFolder.Student__c != null && degreeFolder.Candidate__c != null) {
            files = [
                SELECT Id, Candidate__c, Student__c, Folder__c, File_UUID__c, Storage_Key__c, File_Format__c,
                       Status__c, Comment__c, Name, File_Type__c
                FROM Eligibility_File__c
                WHERE (Student__c = :degreeFolder.Student__c OR Candidate__c = :degreeFolder.Candidate__c)
                  AND Folder__c IN :categoryIds.values()
            ];
        } else if (degreeFolder.Student__c != null) {
            files = [
                SELECT Id, Candidate__c, Student__c, Folder__c, File_UUID__c, Storage_Key__c, File_Format__c,
                       Status__c, Comment__c, Name, File_Type__c
                FROM Eligibility_File__c
                WHERE Student__c = :degreeFolder.Student__c
                  AND Folder__c IN :categoryIds.values()
            ];
        } else {
            files = [
                SELECT Id, Candidate__c, Student__c, Folder__c, File_UUID__c, Storage_Key__c, File_Format__c,
                       Status__c, Comment__c, Name, File_Type__c
                FROM Eligibility_File__c
                WHERE Candidate__c = :degreeFolder.Candidate__c
                  AND Folder__c IN :categoryIds.values()
            ];
        }

        List<EligibilityDatalakeClient.FilePayload> certs = new List<EligibilityDatalakeClient.FilePayload>();
        List<EligibilityDatalakeClient.FilePayload> marks = new List<EligibilityDatalakeClient.FilePayload>();

        for (Eligibility_File__c f : files) {
            EligibilityDatalakeClient.FilePayload fp = mapFileToPayload(f);
            String folderType = getFolderType(categoryIds, f.Folder__c);
            if (folderType == 'Certificates') {
                certs.add(fp);
            } else {
                marks.add(fp);
            }
        }

        EligibilityDatalakeClient.EligibilityResponsePayload payload = new EligibilityDatalakeClient.EligibilityResponsePayload();
        payload.sf_id = uuid;
        payload.qualification_title = String.isNotBlank(degreeFolder.Degree_Title__c) ? degreeFolder.Degree_Title__c : degreeFolder.Name;
        payload.qualification_comment = degreeFolder.Comments__c;
        payload.qualification_status = degreeFolder.Status__c;

        payload.files = new EligibilityDatalakeClient.FilesPayload();
        payload.files.certificates = certs;
        payload.files.mark_sheets = marks;

        // Datalake client already logs request/response for this outbound call.
        EligibilityDatalakeClient.postEligibilityResponse(payload);
    }

    private static void sendFlatFolderPayload(Eligibility_Folder__c flatFolder, String uuid) {
        if (flatFolder == null || String.isBlank(uuid)) {
            logSkipped('sendFlatFolderPayload: missing folder/uuid', null);
            return;
        }

        List<Eligibility_File__c> files;
        if (flatFolder.Student__c != null && flatFolder.Candidate__c != null) {
            files = [
                SELECT Id, Candidate__c, Student__c, Folder__c, File_UUID__c, Storage_Key__c, File_Format__c,
                       Status__c, Comment__c, Name, File_Type__c
                FROM Eligibility_File__c
                WHERE (Student__c = :flatFolder.Student__c OR Candidate__c = :flatFolder.Candidate__c)
                  AND Folder__c = :flatFolder.Id
            ];
        } else if (flatFolder.Student__c != null) {
            files = [
                SELECT Id, Candidate__c, Student__c, Folder__c, File_UUID__c, Storage_Key__c, File_Format__c,
                       Status__c, Comment__c, Name, File_Type__c
                FROM Eligibility_File__c
                WHERE Student__c = :flatFolder.Student__c
                  AND Folder__c = :flatFolder.Id
            ];
        } else {
            files = [
                SELECT Id, Candidate__c, Student__c, Folder__c, File_UUID__c, Storage_Key__c, File_Format__c,
                       Status__c, Comment__c, Name, File_Type__c
                FROM Eligibility_File__c
                WHERE Candidate__c = :flatFolder.Candidate__c
                  AND Folder__c = :flatFolder.Id
            ];
        }

        List<EligibilityDatalakeClient.FilePayload> payloadFiles = new List<EligibilityDatalakeClient.FilePayload>();
        for (Eligibility_File__c f : files) {
            payloadFiles.add(mapFileToPayload(f));
        }

        String flatKey = resolveFlatFolderKey(flatFolder);
        if (String.isBlank(flatKey)) {
            flatKey = flatFolder.Name;
        }

        EligibilityDatalakeClient.FlatEligibilityResponsePayload payload = new EligibilityDatalakeClient.FlatEligibilityResponsePayload();
        payload.sf_id = uuid;
        payload.qualification_title = flatKey;
        payload.qualification_comment = flatFolder.Comments__c;
        payload.qualification_status = flatFolder.Status__c;
        payload.files = payloadFiles;

        // Datalake client already logs request/response for this outbound call.
        EligibilityDatalakeClient.postEligibilityResponseFlat(payload);
    }

    private static String resolveUuidForRecord(Id studentId, Id candidateId) {
        Id primaryId = (studentId != null) ? studentId : candidateId;
        if (primaryId == null) return null;
        EligibilityRecordResolver.Context ctx = EligibilityRecordResolver.resolveByRecordId(primaryId);
        String uuid = EligibilityRecordResolver.resolveUuid(ctx);
        if (String.isBlank(uuid)) {
            uuid = String.valueOf(primaryId);
        }
        return uuid;
    }

    private static void logSkipped(String reason, String requestPayload) {
        IntegrationLogService.log(
            'Outbound status file',
            'Skipped',
            truncate(requestPayload),
            null,
            null,
            reason
        );
    }

    private static String truncate(String value) {
        if (String.isBlank(value)) return value;
        return value.length() > 3000 ? value.substring(0, 3000) : value;
    }

    private static EligibilityDatalakeClient.FilePayload mapFileToPayload(Eligibility_File__c f) {
        EligibilityDatalakeClient.FilePayload fp = new EligibilityDatalakeClient.FilePayload();
        fp.file_type = f.File_Format__c;
        fp.file_path = f.Storage_Key__c;
        fp.file_UUID = f.File_UUID__c;
        fp.file_comment = f.Comment__c;
        fp.file_status = f.Status__c;
        return fp;
    }

    private static Boolean isCertificate(Eligibility_Folder__c folder) {
        if (folder == null || String.isBlank(folder.Folder_Type__c)) return false;
        return folder.Folder_Type__c.toLowerCase().contains('certificate');
    }

    private static String getFolderType(Map<String, Id> typeToId, Id folderId) {
        if (folderId == null || typeToId == null) return null;
        for (String k : typeToId.keySet()) {
            if (typeToId.get(k) == folderId) {
                return k;
            }
        }
        return null;
    }

    private static String resolveFlatFolderKey(Eligibility_Folder__c folder) {
        if (folder == null) return null;
        String key = EligibilityPathParser.normalizeFlatFolderKey(folder.Folder_Type__c);
        if (String.isBlank(key)) key = EligibilityPathParser.normalizeFlatFolderKey(folder.Name);
        if (String.isBlank(key)) key = EligibilityPathParser.normalizeFlatFolderKey(folder.Qualification_Type__c);
        if (String.isBlank(key)) key = EligibilityPathParser.normalizeFlatFolderKey(folder.Degree_Title__c);
        return key;
    }
}