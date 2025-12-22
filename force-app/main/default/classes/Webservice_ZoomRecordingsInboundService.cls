//@RestResource(urlMapping = '/zoom/webinar/recordings/*')
global without sharing class Webservice_ZoomRecordingsInboundService {

    // /* ================= DTO CLASSES ================= */

    // global class FileInfo {
    //     public String file_type;
    //     public String file_path;
    // }

    // global class Payload {
    //     public String sf_id;
    //     public String webinar_id;
    //     public List<FileInfo> files;
    //     public String meeting_start_time;
    //     public String meeting_end_time;
    // }

    // global class ApiResponse {
    //     public Boolean success;
    //     public String message;
    //     public Id webinarId;
    // }

    // /* ================= POST METHOD ================= */

    // @HttpPost
    // global static String doPost() {

    //     RestRequest req = RestContext.request;
    //     RestResponse res = RestContext.response;

    //     String reqBody = (req.requestBody == null) ? '' : req.requestBody.toString();

    //     Integer statusCode = 500;
    //     ApiResponse out = new ApiResponse();
    //     out.success = false;

    //     try {

    //         /* ---------- EMPTY BODY ---------- */
    //         if (String.isBlank(reqBody)) {
    //             statusCode = 400;
    //             out.message = 'Empty request body';
    //         } else {

    //             Payload p;
    //             try {
    //                 p = (Payload) JSON.deserialize(reqBody, Payload.class);
    //             } catch (Exception ex) {
    //                 statusCode = 400;
    //                 out.message = 'Invalid JSON';
    //                 res.statusCode = statusCode;
    //                 return JSON.serialize(out);
    //             }

    //             /* ---------- REQUIRED FIELD ---------- */
    //             if (p == null || String.isBlank(p.webinar_id)) {
    //                 statusCode = 400;
    //                 out.message = 'Missing webinar_id';
    //             } else {

    //                 /* ---------- FIND EXISTING WEBINAR ---------- */
    //                 List<Webinar__c> webinarList = [
    //                     SELECT Id
    //                     FROM Webinar__c
    //                     WHERE Webinar_Id__c = :p.webinar_id
    //                     LIMIT 1
    //                 ];

    //                 if (webinarList.isEmpty()) {
    //                     statusCode = 404;
    //                     out.message = 'Webinar not found';
    //                 } else {

    //                     Webinar__c webinar = webinarList[0];

    //                     /* ---------- DATE PARSING (SAFE) ---------- */
    //                     if (!String.isBlank(p.meeting_start_time)) {
    //                         webinar.Start_Date_Time__c =
    //                             Utility.parseIsoDateTime(p.meeting_start_time);
    //                     }

    //                     if (!String.isBlank(p.meeting_end_time)) {
    //                         webinar.End_Date_Time__c =
    //                             Utility.parseIsoDateTime(p.meeting_end_time);
    //                     }

    //                     /* ---------- FILE MAPPING ---------- */
    //                     String recordingPath;
    //                     String notesPath;

    //                     if (p.files != null) {
    //                         for (FileInfo f : p.files) {
    //                             if (f == null) continue;

    //                             if (String.isBlank(recordingPath)
    //                                 && f.file_type == 'video/mp4') {
    //                                 recordingPath = f.file_path;
    //                             }
    //                             else if (String.isBlank(notesPath)
    //                                 && f.file_type == 'application/pdf') {
    //                                 notesPath = f.file_path;
    //                             }
    //                         }
    //                     }

    //                     /* ---------- UPDATE ONLY REQUIRED FIELDS ---------- */
    //                     webinar.Recording_File_Path__c = recordingPath;
    //                     webinar.Notes_File_Path__c     = notesPath;

    //                     update webinar;

    //                     statusCode = 200;
    //                     out.success = true;
    //                     out.message = 'Webinar recording data updated successfully';
    //                     out.webinarId = webinar.Id;
    //                 }
    //             }
    //         }

    //     } catch (Exception e) {
    //         statusCode = 500;
    //         out.message = 'Unhandled error: ' + e.getMessage();
    //     }

    //     res.statusCode = statusCode;
    //     return JSON.serialize(out);
    // }
}