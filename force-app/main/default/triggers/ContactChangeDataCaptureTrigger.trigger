trigger ContactChangeDataCaptureTrigger on ContactChangeEvent (after insert) {
    for(ContactChangeEvent event : Trigger.New) {
        EventBus.ChangeEventHeader header = event.ChangeEventHeader;
        
        // Simple one-line JSON creation
        String jsonOutput = JSON.serializePretty(new Map<String, Object>{
            'changeType' => header.changetype,
            'recordIds' => header.recordids,
            'changedFields' => header.changedfields,
            'firstName' => event.FirstName,
            'lastName' => event.LastName,
            'email' => event.Email,
            'phone' => event.Phone,
            'title' => event.Title,
            'department' => event.Department,
            'timestamp' => System.now()
        });
        
        System.debug('CDC Contact JSON: ' + jsonOutput);
    }
}