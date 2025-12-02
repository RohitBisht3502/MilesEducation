public without sharing class EligibilityFileService {

    public class IncomingFile {
        public String uuid;
        public String path;
        public String format;
        public String fileType; // "Certificate" / "Marksheet"
    }

    public class NewQualificationRequest {
        public String salesforceId;           // Lead__c.Id
        public String qualificationType;      // UG / PG / Certification
        public String qualificationTitle;     // B.Com, CA-Inter
        public String qualificationMonthYear; // e.g. "June 2024"
        public List<IncomingFile> certificateFiles;
        public List<IncomingFile> marksheetFiles;
    }

    public class ApiResponse {
        public Boolean success;
        public String message;
    }

    // ---------- NEW IMPLEMENTATION ----------
    public static ApiResponse handleNewQualification(NewQualificationRequest input) {
        ApiResponse res = new ApiResponse();
        res.success = false;

        if (input == null || String.isBlank(input.salesforceId)) {
            res.message = 'Missing Lead Id.';
            return res;
        }

        Id leadId = (Id) input.salesforceId;

        if (String.isBlank(input.qualificationType) || String.isBlank(input.qualificationTitle)) {
            res.message = 'Missing qualification type or title.';
            return res;
        }

        // Find or create degree folder and its category folders
        Eligibility_Folder__c degreeFolder =
            EligibilityFolderService.findDegreeFolder(
                leadId,
                input.qualificationType,
                input.qualificationTitle
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

        res.success = true;
        res.message = 'Qualification files synced successfully.';
        return res;
    }

    // ---------- HELPER: sync by File_UUID__c per folder ----------
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
			SELECT Id, Lead__c, Folder__c, File_UUID__c, Status__c,
				   Storage_Key__c, File_Format__c, File_Type__c
			FROM Eligibility_File__c
			WHERE Lead__c = :leadId
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
	
		for (IncomingFile f : incoming) {
			if (f == null || String.isBlank(f.uuid) || String.isBlank(f.path)) continue;
	
			incomingUuids.add(f.uuid);
	
			Eligibility_File__c ex = existingByUuid.get(f.uuid);
	
			// If exists with same UUID: do NOT change anything, just keep it.
			if (ex != null) {
				continue;
			} else {
				// New UUID -> insert new file
				// New UUID -> insert new file
			Eligibility_File__c nf = new Eligibility_File__c();
			nf.Lead__c        = leadId;
			nf.Folder__c      = folderId;
			nf.File_UUID__c   = f.uuid;
			nf.Storage_Key__c = f.path;
			nf.File_Format__c = f.format;
			nf.File_Type__c   = logicalFileType;
			nf.Status__c      = 'Submitted';

			// derive name from path: last segment after '/'
			String fileName = f.path;
			if (!String.isBlank(fileName) && fileName.contains('/')) {
				List<String> parts = fileName.split('/');
				fileName = parts[parts.size() - 1];
			}
			nf.Name = fileName;

			toUpsert.add(nf);
			affectedFolderIds.add(folderId);

			}
		}
	
		// Delete extra files whose UUID is not present in incoming list
		for (Eligibility_File__c ef : existing) {
			if (String.isBlank(ef.File_UUID__c)) {
				continue;
			}
			if (!incomingUuids.contains(ef.File_UUID__c)) {
				toDelete.add(ef);
				affectedFolderIds.add(folderId);
			}
		}
	}
}