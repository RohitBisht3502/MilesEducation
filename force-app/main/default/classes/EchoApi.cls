@RestResource(urlMapping='/gp-file-status-update/*')
global without sharing class EchoApi {

    @HttpPost
    global static void doPost() {

        String body = RestContext.request.requestBody == null ? '' : RestContext.request.requestBody.toString();
        Integer statusCode = 200;
        Object resPayload;

        System.debug('EchoApi request body => ' + body);

        try {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(body);

            String uuid    = (String) payload.get('uuid');
            String level   = (String) payload.get('level');
            String program = (String) payload.get('program');
            String step    = (String) payload.get('step');

            System.debug('EchoApi parsed => uuid=' + uuid + ', level=' + level + ', program=' + program + ', step=' + step);

            if (String.isBlank(uuid) || String.isBlank(level) || String.isBlank(program) || String.isBlank(step)) {
                statusCode = 400;
                resPayload = new Map<String, Object>{
                    'status' => 'failed',
                    'message' => 'UUID or Level or Program or Step missing'
                };
                System.debug('EchoApi validation failed => ' + resPayload);

                IntegrationLogUtil.insertLog('GP Level Update API', body, JSON.serialize(resPayload), 'Validation Failed', 'Failed', statusCode);
                sendJsonResponse(statusCode, resPayload);
                return;
            }

            Lead candidate = [SELECT Id FROM Lead WHERE UUID__c = :uuid LIMIT 1];
            Lead__c lead = [SELECT Id, Stage__c, Student__c FROM Lead__c WHERE Candidate__c = :candidate.Id AND Course__c = :program LIMIT 1];

            System.debug('EchoApi leadStage => LeadId=' + candidate.Id + ', CandidateId=' + lead.Id + ', OldStage=' + lead.Stage__c);

            lead.Stage__c = level;
            update lead;

            System.debug('EchoApi leadStage => Updated Candidate Stage=' + level);

            Id gpFolderId = createOrUpdateGpFolder(payload, uuid, program, level, step, lead.Student__c);
            createOrUpdateStudentFiles(payload, program, candidate.Id, lead.Id, lead.Student__c, level, gpFolderId);

            resPayload = new Map<String, Object>{
                'uuid' => uuid,
                'level' => level,
                'program' => program,
                'status' => 'success'
            };

            System.debug('EchoApi response => ' + resPayload);

            IntegrationLogUtil.insertLog('GP Level Update API', body, JSON.serialize(resPayload), 'Success', 'Success', 200);
            sendJsonResponse(200, resPayload);

        } catch (Exception e) {
            statusCode = 500;
            resPayload = new Map<String, Object>{
                'status' => 'failed',
                'message' => 'Error: ' + e.getMessage()
            };
            System.debug('EchoApi exception => ' + resPayload);

            IntegrationLogUtil.insertLog('GP Level Update API', body, JSON.serialize(resPayload), 'Unhandled Error', 'Failed', statusCode);
            sendJsonResponse(statusCode, resPayload);
        }
    }

    private static void sendJsonResponse(Integer statusCode, Object payload) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(payload));
    }

    private static Id createOrUpdateGpFolder(
        Map<String, Object> payload,
        String uuid,
        String program,
        String level,
        String step,
        Id studentId
    ) {
        String folderPath = buildFolderPath(uuid, program, step);

        List<GP_Folder__c> existingFolders = [
            SELECT Id
            FROM GP_Folder__c
            WHERE UUID__c = :uuid
            AND Program__c = :program
            AND Step__c = :step
            LIMIT 1
        ];

        GP_Folder__c folderRecord = existingFolders.isEmpty()
            ? new GP_Folder__c()
            : existingFolders[0];

        folderRecord.Name = uuid + ' - ' + program + ' - ' + step;
        folderRecord.UUID__c = uuid;
        folderRecord.Program__c = program;
        folderRecord.Level__c = level;
        folderRecord.Step__c = step;
        folderRecord.Folder_Path__c = folderPath;
        folderRecord.Student__c = studentId;

        upsert folderRecord;
        return folderRecord.Id;
    }

    private static String buildFolderPath(String uuid, String program, String step) {
        if (String.isBlank(uuid) || String.isBlank(program) || String.isBlank(step)) {
            return null;
        }

        return uuid + '/gp_tool/' + program + '/' + step + '/';
    }

    private static void createOrUpdateStudentFiles(
        Map<String, Object> payload,
        String program,
        Id candidateId,
        Id leadId,
        Id studentId,
        String level,
        Id gpFolderId
    ) {
        if (payload == null || !payload.containsKey('files') || payload.get('files') == null) {
            System.debug('StudentFiles => files missing, skipping');
            return;
        }

        List<Object> raw = (List<Object>) payload.get('files');
        if (raw == null || raw.isEmpty()) {
            System.debug('StudentFiles => files empty, skipping');
            return;
        }

        System.debug('StudentFiles => incoming records count=' + raw.size());

        Set<String> fileUuids = new Set<String>();
        for (Object o : raw) {
            if (o instanceof Map<String, Object>) {
                String fileUuid = (String) ((Map<String, Object>) o).get('file_UUID');
                if (!String.isBlank(fileUuid)) fileUuids.add(fileUuid);
            }
        }
        if (fileUuids.isEmpty()) {
            System.debug('StudentFiles => no file_UUID found, skipping');
            return;
        }

        System.debug('StudentFiles => fileUUIDs=' + fileUuids);

        List<Student_File_Status__c> existing = [
            SELECT Id, File_UUID__c
            FROM Student_File_Status__c
            WHERE File_UUID__c IN :fileUuids
        ];

        System.debug('StudentFiles => existing found=' + existing.size());

        Map<String, Id> fileUuidToId = new Map<String, Id>();
        for (Student_File_Status__c r : existing) {
            fileUuidToId.put(r.File_UUID__c, r.Id);
        }

        List<Student_File_Status__c> ins = new List<Student_File_Status__c>();
        List<Student_File_Status__c> upd = new List<Student_File_Status__c>();

        for (Object o : raw) {
            if (!(o instanceof Map<String, Object>)) continue;

            Map<String, Object> d = (Map<String, Object>) o;
            String fileUuid = (String) d.get('file_UUID');
            String fileType = (String) d.get('file_type');
            if (String.isBlank(fileUuid) || String.isBlank(fileType)) continue;

            Student_File_Status__c rec = new Student_File_Status__c();
            rec.GP_Folder__c = gpFolderId;
            rec.File_UUID__c = fileUuid;
            rec.File_Name__c = (String) d.get('file_name');
            rec.File_Type__c = fileType;
            rec.Status__c = (String) d.get('status');
            rec.Comment__c = (String) d.get('comment');
            rec.File_Path__c = (String) d.get('file_path');
            rec.File_Ext__c = (String) d.get('file_ext');
            rec.Course__c = program;
            rec.Level__c = level;
            rec.Lead__c = leadId;
            rec.Candidate__c = candidateId;
            rec.Student__c = studentId;

            if (fileUuidToId.containsKey(fileUuid)) {
                rec.Id = fileUuidToId.get(fileUuid);
                upd.add(rec);
            } else {
                ins.add(rec);
            }
        }

        System.debug('StudentFiles => toInsert=' + ins.size() + ', toUpdate=' + upd.size());

        if (!ins.isEmpty()) insert ins;
        if (!upd.isEmpty()) update upd;

        System.debug('StudentFiles => done');
    }
}