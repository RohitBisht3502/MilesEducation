@RestResource(urlMapping='/gmeet/recordings/*')
global without sharing class Webservice_GMeetRecordingsInboundService {

    global class FileInfo {
        public String file_type;
        public String file_path;
    }

    global class Payload {
        public String sf_id;
        public String event_id;
        public List<FileInfo> files;
        public Integer mutual_meeting_seconds;
        public String meeting_start_time;
        public String meeting_end_time;
    }

    global class ApiResponse {
        public Boolean success;
        public String message;
        public Id eventId;
    }

    @HttpPost
    global static String doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String reqBody = (req.requestBody == null) ? '' : req.requestBody.toString();

        Integer statusCode = 500;
        ApiResponse out = new ApiResponse();
        out.success = false;

        try {
            if (String.isBlank(reqBody)) {
                statusCode = 400;
                out.message = 'Empty request body';
                IntegrationLogUtil.insertLog('GMeet Recordings Inbound', null, null, out.message, 'Failed', statusCode);
            } else {
                Payload p;
                try {
                    p = (Payload) JSON.deserialize(reqBody, Payload.class);
                } catch (Exception ex) {
                    statusCode = 400;
                    out.message = 'Invalid JSON';
                    IntegrationLogUtil.insertLog('GMeet Recordings Inbound', reqBody, null, 'Invalid JSON: ' + ex.getMessage(), 'Failed', statusCode);
                    res.statusCode = statusCode;
                    return JSON.serialize(out);
                }

                if (p == null || String.isBlank(p.event_id)) {
                    statusCode = 400;
                    out.message = 'Missing event_id';
                    IntegrationLogUtil.insertLog('GMeet Recordings Inbound', reqBody, null, out.message, 'Failed', statusCode);
                } else {
                    List<Event> evts = [SELECT Id, Event_Id__c ,EndDateTime , StartDateTime, Mutual_Meeting_Seconds__c ,Recording_File_Path__c,Notes_File_Path__c FROM Event WHERE Event_Id__c = :p.event_id LIMIT 1];

                    if (evts.isEmpty()) {
                        statusCode = 404;
                        out.message = 'Event not found';
                        IntegrationLogUtil.insertLog('GMeet Recordings Inbound', reqBody, null, 'Event not found for event_id: ' + p.event_id, 'Failed', statusCode);
                    } else {
                        Event ev = evts[0];

                        DateTime startDt = Utility.parseIsoDateTime(p.meeting_start_time);
                        DateTime endDt   = Utility.parseIsoDateTime(p.meeting_end_time);

                        ev.put('StartDateTime', startDt);
                        ev.put('EndDateTime', endDt);
                        ev.put('Mutual_Meeting_Seconds__c', p.mutual_meeting_seconds);

                        String videoPath;
                        String notesPath;

                        if (p.files != null) {
                            for (FileInfo f : p.files) {
                                if (f == null) continue;
                                if (String.isBlank(videoPath) && f.file_type == 'video/mp4') {
                                    videoPath = f.file_path;
                                } else if (String.isBlank(notesPath) && f.file_type == 'application/pdf') {
                                    notesPath = f.file_path;
                                }
                            }
                        }

                        ev.put('Recording_File_Path__c', videoPath);
                        ev.put('Notes_File_Path__c', notesPath);
                       // ev.put('GMeet_Recording_Payload__c', reqBody);

                        update ev;

                        statusCode = 200;
                        out.success = true;
                        out.message = 'Meeting recording details saved successfully';
                        out.eventId = ev.Id;

                        IntegrationLogUtil.insertLog('GMeet Recordings Inbound', reqBody, 'Updated Event: ' + ev.Id, 'Success', 'Success', statusCode);
                    }
                }
            }
        } catch (Exception e) {
            statusCode = 500;
            out.success = false;
            out.message = 'Unhandled error';
            IntegrationLogUtil.insertLog('GMeet Recordings Inbound', reqBody, null, 'Unhandled error: ' + e.getMessage(), 'Failed', statusCode);
        }

        res.statusCode = statusCode;
        return JSON.serialize(out);
    }

}