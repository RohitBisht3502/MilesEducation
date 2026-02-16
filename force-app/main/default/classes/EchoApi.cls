@RestResource(urlMapping='/echo/*')
global without sharing class EchoApi {

    private static Boolean isLeadStage(String level) {
        return new Set<String>{'M1','M2','M3','M3+','M3++','M4-','M4','M5','M6','M7'}.contains(level);
    }

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

            System.debug('EchoApi parsed => uuid=' + uuid + ', level=' + level + ', program=' + program);

            if (String.isBlank(uuid) || String.isBlank(level) || String.isBlank(program)) {
                statusCode = 400;
                resPayload = new Map<String, Object>{
                    'status' => 'failed',
                    'message' => 'UUID or Level or Program missing'
                };
                System.debug('EchoApi validation failed => ' + resPayload);

                IntegrationLogUtil.insertLog('GP Level Update API', body, JSON.serialize(resPayload), 'Validation Failed', 'Failed', statusCode);
                sendJsonResponse(statusCode, resPayload);
                return;
            }

            if (isLeadStage(level)) {

                Lead candidate = [SELECT Id FROM Lead WHERE UUID__c = :uuid LIMIT 1];
                Lead__c lead = [SELECT Id, Stage__c FROM Lead__c WHERE Candidate__c = :candidate.Id AND Course__c = :program LIMIT 1];

                System.debug('EchoApi leadStage => LeadId=' + candidate.Id + ', CandidateId=' + lead.Id + ', OldStage=' + lead.Stage__c);

                lead.Stage__c = level;
                update lead;

                System.debug('EchoApi leadStage => Updated Candidate Stage=' + level);

                createOrUpdateStudentFiles(payload, program, candidate.Id, lead.Id, null, null,level);

            } else {

                Account a = [SELECT Id FROM Account WHERE UUID__c = :uuid LIMIT 1];
                Course_Enrolled__c ce = [SELECT Id, Stages__c FROM Course_Enrolled__c WHERE Student__c = :a.Id AND Course__c = :program LIMIT 1];

                System.debug('EchoApi studentStage => AccountId=' + a.Id + ', CourseEnrolledId=' + ce.Id + ', OldStage=' + ce.Stages__c);

                ce.Stages__c = level;
                update ce;

                System.debug('EchoApi studentStage => Updated CourseEnrolled Stage=' + level);

                createOrUpdateStudentFiles(payload, program, null, null, a.Id, ce.Id,level);
            }

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

    private static void createOrUpdateStudentFiles(
        Map<String, Object> payload,
        String program,
        Id candidateId,
        Id leadId,
        Id accountId,
        Id courseEnrolledId,
        String level
    ) {
        if (payload == null || !payload.containsKey('files_status') || payload.get('files_status') == null) {
            System.debug('StudentFiles => files_status missing, skipping');
            return;
        }

        List<Object> raw = (List<Object>) payload.get('files_status');
        if (raw == null || raw.isEmpty()) {
            System.debug('StudentFiles => files_status empty, skipping');
            return;
        }

        System.debug('StudentFiles => incoming records count=' + raw.size());

        Set<String> fileTypes = new Set<String>();
        for (Object o : raw) {
            if (o instanceof Map<String, Object>) {
                String ft = (String) ((Map<String, Object>) o).get('file_type');
                if (!String.isBlank(ft)) fileTypes.add(ft);
            }
        }
        if (fileTypes.isEmpty()) {
            System.debug('StudentFiles => no file_type found, skipping');
            return;
        }

        System.debug('StudentFiles => fileTypes=' + fileTypes);

        List<Student_File_Status__c> existing;

        if (leadId != null || candidateId != null) {
            existing = [
                SELECT Id, File_Type__c
                FROM Student_File_Status__c
                WHERE Course__c = :program
                AND File_Type__c IN :fileTypes
                AND (Lead__c = :leadId OR Candidate__c = :candidateId)
            ];
        } else {
            existing = [
                SELECT Id, File_Type__c
                FROM Student_File_Status__c
                WHERE Course__c = :program
                AND File_Type__c IN :fileTypes
                AND (Student__c = :accountId OR Course_Enrolled__c = :courseEnrolledId)
            ];
        }

        System.debug('StudentFiles => existing found=' + existing.size());

        Map<String, Id> fileTypeToId = new Map<String, Id>();
        for (Student_File_Status__c r : existing) fileTypeToId.put(r.File_Type__c, r.Id);

        List<Student_File_Status__c> ins = new List<Student_File_Status__c>();
        List<Student_File_Status__c> upd = new List<Student_File_Status__c>();

        for (Object o : raw) {
            if (!(o instanceof Map<String, Object>)) continue;

            Map<String, Object> d = (Map<String, Object>) o;
            String fileType = (String) d.get('file_type');
            if (String.isBlank(fileType)) continue;

            Student_File_Status__c rec = new Student_File_Status__c();
            rec.File_Type__c = fileType;
            rec.Status__c = (String) d.get('status');
            rec.Comment__c = (String) d.get('comment');
            rec.File_Path__c = (String) d.get('file_path');
            rec.Course__c = program;
            rec.Level__c = level;
            rec.Lead__c = leadId;
            rec.Candidate__c = candidateId;
            rec.Student__c = accountId;
            rec.Course_Enrolled__c = courseEnrolledId;

            if (fileTypeToId.containsKey(fileType)) {
                rec.Id = fileTypeToId.get(fileType);
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