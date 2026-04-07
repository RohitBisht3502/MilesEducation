@RestResource(urlMapping='/gp-file-status-updates/*')
global without sharing class GpFileStatusUpdateApi {
    private static final String INTEGRATION_NAME = 'GP Level Update API';

    global class RequestPayload {
        public String uuid;
        public String level;
        public String program;
        public String step;
        public List<FilePayload> files;
    }

    global class FilePayload {
        public String file_UUID;
        public String file_name;
        public String file_type;
        public String status;
        public String comment;
        public String file_path;
        public String file_ext;
    }

    global class ResponsePayload {
        public String status;
        public String message;
        public String uuid;
        public String level;
        public String program;
        public String step;
    }

    private class ApiValidationException extends Exception {}

    @HttpPost
    global static void doPost() {
        String requestBody = RestContext.request.requestBody == null
            ? ''
            : RestContext.request.requestBody.toString();

        try {
            RequestPayload request = (RequestPayload) JSON.deserialize(requestBody, RequestPayload.class);
            validateRequest(request);

            Lead candidate = fetchCandidate(request.uuid);
            Lead__c relatedLead = fetchLead(candidate.Id, request.program);

            relatedLead.Stage__c = request.level;
            update relatedLead;

            Id gpFolderId = upsertGpFolder(request, candidate.Id, relatedLead.Id, relatedLead.Student__c);
            upsertStudentFiles(request, candidate.Id, relatedLead.Id, relatedLead.Student__c, gpFolderId);

            ResponsePayload response = buildSuccessResponse(request);
            logAndRespond(200, response, requestBody, 'Success', 'Success');
        } catch (ApiValidationException ex) {
            logAndRespond(400, buildErrorResponse(ex.getMessage()), requestBody, 'Validation Failed', 'Failed');
        } catch (Exception ex) {
            logAndRespond(500, buildErrorResponse('Error: ' + ex.getMessage()), requestBody, 'Unhandled Error', 'Failed');
        }
    }

    private static void validateRequest(RequestPayload request) {
        if (request == null) {
            throw new ApiValidationException('Request body is missing.');
        }

        if (
            String.isBlank(request.uuid) ||
            String.isBlank(request.level) ||
            String.isBlank(request.program) ||
            String.isBlank(request.step)
        ) {
            throw new ApiValidationException('UUID, Level, Program, and Step are required.');
        }
    }

    private static Lead fetchCandidate(String uuid) {
        try {
            return [SELECT Id FROM Lead WHERE UUID__c = :uuid LIMIT 1];
        } catch (QueryException ex) {
            throw new ApiValidationException('No candidate found for the provided UUID.');
        }
    }

    private static Lead__c fetchLead(Id candidateId, String program) {
        try {
            return [SELECT Id, Stage__c, Student__c FROM Lead__c WHERE Candidate__c = :candidateId AND Course__c = :program LIMIT 1];
        } catch (QueryException ex) {
            throw new ApiValidationException('No lead found for the provided program.');
        }
    }

    private static Id upsertGpFolder(RequestPayload request, Id candidateId, Id leadId, Id studentId) {
        String folderPath = buildFolderPath(request.uuid, request.program, request.step);
        List<GP_Folder__c> existingFolders = [SELECT Id FROM GP_Folder__c WHERE UUID__c = :request.uuid AND Program__c = :request.program AND Step__c = :request.step LIMIT 1];

        GP_Folder__c folderRecord = existingFolders.isEmpty() ? new GP_Folder__c() : existingFolders[0];
        folderRecord.UUID__c = request.uuid;
        folderRecord.Program__c = request.program;
        folderRecord.Level__c = request.level;
        folderRecord.Step__c = request.step;
        folderRecord.Folder_Path__c = folderPath;
        folderRecord.Status__c = deriveFolderStatus(request.files);
        folderRecord.Candidate__c = candidateId;
        folderRecord.Lead__c = leadId;
        folderRecord.Student__c = studentId;

        upsert folderRecord;
        return folderRecord.Id;
    }

    private static void upsertStudentFiles(RequestPayload request, Id candidateId, Id leadId, Id studentId, Id gpFolderId) {
        if (request.files == null || request.files.isEmpty()) {
            return;
        }

        Set<String> fileUuids = new Set<String>();
        for (FilePayload file : request.files) {
            if (!String.isBlank(file.file_UUID)) {
                fileUuids.add(file.file_UUID);
            }
        }

        if (fileUuids.isEmpty()) {
            return;
        }

        Map<String, Student_File_Status__c> existingByUuid = new Map<String, Student_File_Status__c>();
        for (Student_File_Status__c existingRecord : [SELECT Id, File_UUID__c FROM Student_File_Status__c WHERE File_UUID__c IN :fileUuids]) {
            existingByUuid.put(existingRecord.File_UUID__c, existingRecord);
        }

        List<Student_File_Status__c> recordsToInsert = new List<Student_File_Status__c>();
        List<Student_File_Status__c> recordsToUpdate = new List<Student_File_Status__c>();

        for (FilePayload file : request.files) {
            if (file == null || String.isBlank(file.file_UUID) || String.isBlank(file.file_type)) {
                continue;
            }

            Student_File_Status__c fileRecord = new Student_File_Status__c();
            fileRecord.GP_Folder__c = gpFolderId;
            fileRecord.File_UUID__c = file.file_UUID;
            fileRecord.File_Name__c = file.file_name;
            fileRecord.File_Type__c = file.file_type;
            fileRecord.Status__c = file.status;
            fileRecord.Comment__c = file.comment;
            fileRecord.File_Path__c = file.file_path;
            fileRecord.File_Ext__c = file.file_ext;
            fileRecord.Course__c = request.program;
            fileRecord.Level__c = request.level;
            fileRecord.Lead__c = leadId;
            fileRecord.Candidate__c = candidateId;
            fileRecord.Student__c = studentId;

            if (existingByUuid.containsKey(file.file_UUID)) {
                fileRecord.Id = existingByUuid.get(file.file_UUID).Id;
                recordsToUpdate.add(fileRecord);
            } else {
                recordsToInsert.add(fileRecord);
            }
        }

        if (!recordsToInsert.isEmpty()) {
            insert recordsToInsert;
        }

        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
    }

    private static ResponsePayload buildSuccessResponse(RequestPayload request) {
        ResponsePayload response = new ResponsePayload();
        response.status = 'success';
        response.uuid = request.uuid;
        response.level = request.level;
        response.program = request.program;
        response.step = request.step;
        return response;
    }

    private static ResponsePayload buildErrorResponse(String message) {
        ResponsePayload response = new ResponsePayload();
        response.status = 'failed';
        response.message = message;
        return response;
    }

    private static String buildFolderPath(String uuid, String program, String step) {
        if (String.isBlank(uuid) || String.isBlank(program) || String.isBlank(step)) {
            return null;
        }
        return uuid + '/gp_tool/' + program + '/' + step + '/';
    }

    private static String deriveFolderStatus(List<FilePayload> files) {
        if (files == null || files.isEmpty() || files[0] == null) {
            return null;
        }
        return files[0].status;
    }

    private static void logAndRespond(Integer statusCode, ResponsePayload responsePayload, String requestBody, String logStage, String logStatus) {
        IntegrationLogUtil.insertLog(
            INTEGRATION_NAME,
            requestBody,
            JSON.serialize(responsePayload),
            logStage,
            logStatus,
            statusCode
        );
        sendJsonResponse(statusCode, responsePayload);
    }

    private static void sendJsonResponse(Integer statusCode, ResponsePayload payload) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(payload));
    }
}
