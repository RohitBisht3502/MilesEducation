// Builds and sends eligibility status updates to the datalake.
public without sharing class EligibilityResponseService {

    @future(callout=true)
    public static void sendForFile(Id fileId) {
        if (fileId == null) return;

        Eligibility_File__c file = [
            SELECT Id, Lead__c, Folder__c, File_UUID__c, Storage_Key__c, File_Format__c,
                   Status__c, Comment__c, Name, File_Type__c
            FROM Eligibility_File__c
            WHERE Id = :fileId
            LIMIT 1
        ];

        if (file.Lead__c == null || file.Folder__c == null) return;

        // Get category + degree folders
        Eligibility_Folder__c categoryFolder = [
            SELECT Id, Name, Folder_Type__c, Parent_Folder__c
            FROM Eligibility_Folder__c
            WHERE Id = :file.Folder__c
            LIMIT 1
        ];

        Eligibility_Folder__c degreeFolder = null;
        if (categoryFolder.Parent_Folder__c != null) {
            degreeFolder = [
                SELECT Id, Name, Degree_Title__c, Status__c, Comments__c
                FROM Eligibility_Folder__c
                WHERE Id = :categoryFolder.Parent_Folder__c
                LIMIT 1
            ];
        }

        if (degreeFolder == null) return;

        EligibilityDatalakeClient.EligibilityResponsePayload payload = new EligibilityDatalakeClient.EligibilityResponsePayload();
        payload.sf_id = String.valueOf(file.Lead__c);
        payload.qualification_title = String.isNotBlank(degreeFolder.Degree_Title__c) ? degreeFolder.Degree_Title__c : degreeFolder.Name;
        payload.qualification_comment = degreeFolder.Comments__c;
        payload.qualification_status = degreeFolder.Status__c;

        EligibilityDatalakeClient.FilePayload fp = mapFileToPayload(file);

        payload.files = new EligibilityDatalakeClient.FilesPayload();
        if (isCertificate(categoryFolder)) {
            payload.files.certificates = new List<EligibilityDatalakeClient.FilePayload>{ fp };
            payload.files.mark_sheets = new List<EligibilityDatalakeClient.FilePayload>();
        } else {
            payload.files.mark_sheets = new List<EligibilityDatalakeClient.FilePayload>{ fp };
            payload.files.certificates = new List<EligibilityDatalakeClient.FilePayload>();
        }

        EligibilityDatalakeClient.postEligibilityResponse(payload);
    }

    @future(callout=true)
    public static void sendForDegreeFolder(Id folderId) {
        if (folderId == null) return;

        Eligibility_Folder__c degreeFolder = [
            SELECT Id, Lead__c, Name, Degree_Title__c, Status__c, Comments__c
            FROM Eligibility_Folder__c
            WHERE Id = :folderId
            LIMIT 1
        ];
        if (degreeFolder.Lead__c == null) return;

        // Collect category folders and their files
        Map<String, Id> categoryIds = new Map<String, Id>();
        for (Eligibility_Folder__c cf : [
            SELECT Id, Folder_Type__c
            FROM Eligibility_Folder__c
            WHERE Parent_Folder__c = :degreeFolder.Id
        ]) {
            categoryIds.put(cf.Folder_Type__c, cf.Id);
        }

        List<Eligibility_File__c> files = [
            SELECT Id, Lead__c, Folder__c, File_UUID__c, Storage_Key__c, File_Format__c,
                   Status__c, Comment__c, Name, File_Type__c
            FROM Eligibility_File__c
            WHERE Lead__c = :degreeFolder.Lead__c
              AND Folder__c IN :categoryIds.values()
        ];

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
        payload.sf_id = String.valueOf(degreeFolder.Lead__c);
        payload.qualification_title = String.isNotBlank(degreeFolder.Degree_Title__c) ? degreeFolder.Degree_Title__c : degreeFolder.Name;
        payload.qualification_comment = degreeFolder.Comments__c;
        payload.qualification_status = degreeFolder.Status__c;

        payload.files = new EligibilityDatalakeClient.FilesPayload();
        payload.files.certificates = certs;
        payload.files.mark_sheets = marks;

        EligibilityDatalakeClient.postEligibilityResponse(payload);
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
}