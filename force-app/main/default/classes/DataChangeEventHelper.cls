public class DataChangeEventHelper {

public static void publishEvents(List<SObject> newList, Map<Id, SObject> oldMap, String type) {
    List<Montier_Change__e> events = new List<Montier_Change__e>();

    for (SObject rec : newList) {
        Map<String, Object> currentData = rec.getPopulatedFieldsAsMap();
        Map<String, Object> allData = getAllFieldData(rec);
        Map<String, Object> metadata = new Map<String, Object>{
            'changeType' => oldMap == null ? 'CREATE' : 'UPDATE',
            'recordIds' => new List<Id>{ rec.Id },
            'objectType' => type,
            'updatedBy' => UserInfo.getName(),
            'timestamp' => System.now()
        };

        List<String> changedFields = new List<String>();

        if (oldMap == null) {
            changedFields.addAll(currentData.keySet());
        } else {
            SObject oldRec = oldMap.get(rec.Id);
            Map<String, Object> oldMapValues = oldRec != null
                ? oldRec.getPopulatedFieldsAsMap()
                : new Map<String, Object>();

            Set<String> fieldNames = new Set<String>();
            fieldNames.addAll(currentData.keySet());
            fieldNames.addAll(oldMapValues.keySet());

            for (String field : fieldNames) {
                Object newVal = currentData.get(field);
                Object oldVal = oldMapValues.get(field);

                if (newVal != oldVal) {
                    changedFields.add(field);
                }
            }
        }

        Map<String, Object> payload = new Map<String, Object>{
            'metadata' => metadata,
            'changedFields' => changedFields,
            'currentData' => currentData,
            'allData' => allData
        };

        // Convert to JSON
        String jsonPayload = JSON.serializePretty(payload);
        System.debug('jsonPayload>> '+jsonPayload);

        // Create Event
        Montier_Change__e evt = new Montier_Change__e();
        evt.Changed_Data__c = jsonPayload;
        evt.Type__c = type;
        evt.Updated_by__c = UserInfo.getName();

        events.add(evt);
    }

    if (!events.isEmpty()) {
        EventBus.publish(events);
    }
}

private static Map<String, Object> getAllFieldData(SObject recordData) {
    Map<String, Object> allData = new Map<String, Object>();
    if (recordData == null) {
        return allData;
    }

    Map<String, Schema.SObjectField> fieldMap = recordData.getSObjectType().getDescribe().fields.getMap();
    for (String fieldApi : fieldMap.keySet()) {
        allData.put(fieldApi, recordData.get(fieldApi));
    }

    return allData;
}
}