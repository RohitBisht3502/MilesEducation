public with sharing class EventRecordingLinksController {
    public class EventFileInfo {
        @AuraEnabled public String recordingPath;
        @AuraEnabled public String notesPath;
    }

    @AuraEnabled(cacheable=true)
    public static EventFileInfo getEventFileInfo(Id recordId) {
        if (recordId == null) {
            return null;
        }

        List<Event> evts = [
            SELECT Recording_File_Path__c, Notes_File_Path__c
            FROM Event
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (evts.isEmpty()) {
            return null;
        }

        EventFileInfo info = new EventFileInfo();
        info.recordingPath = (String) evts[0].get('Recording_File_Path__c');
        info.notesPath = (String) evts[0].get('Notes_File_Path__c');
        return info;
    }
}