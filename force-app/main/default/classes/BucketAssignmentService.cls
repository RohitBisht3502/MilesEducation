/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public class BucketAssignmentService {

    public static void assignBucket(List<SObject> newList, Map<Id, SObject> oldMap) {
        if (newList == null || newList.isEmpty()) return;

        List<SObject> toProcess = new List<SObject>();

        Set<String> courseValues = new Set<String>();
        Set<String> sourceValues = new Set<String>();

        // Detect changes
        for (SObject newRec : newList) {

            if (oldMap == null) {
                toProcess.add(newRec); // INSERT
            } else { // Update
                SObject oldRec = oldMap.get((Id)newRec.get('Id'));
                if (oldRec == null) continue;

                Boolean courseChanged =
                    hasField(newRec, 'Course__c') &&
                    newRec.get('Course__c') != oldRec.get('Course__c');

                Boolean sourceChanged =
                    (hasField(newRec, 'Source__c') &&
                     newRec.get('Source__c') != oldRec.get('Source__c'))
                    ||
                    (newRec.getSObjectType() == Lead.SObjectType &&
                     newRec.get('Coming_From__c') != oldRec.get('Coming_From__c'));

                if (courseChanged || sourceChanged) {
                    toProcess.add(newRec);
                }
            }
        }

        if (toProcess.isEmpty()) return;

        //  Collect values
        for (SObject sob : toProcess) {

            if (hasField(sob, 'Course__c')) {
                String c = (String)sob.get('Course__c');
                if (String.isNotBlank(c)) courseValues.add(c);
            }

            if (hasField(sob, 'Source__c')) {
                String s = (String)sob.get('Source__c');
                if (String.isNotBlank(s)) sourceValues.add(s);
            }
            else if (sob.getSObjectType() == Lead.SObjectType) {
                String ls = (String)sob.get('Coming_From__c');
                if (String.isNotBlank(ls)) sourceValues.add(ls);
            }
        }

        // CMDT lookup
        Map<String, String> courseBucketMap = new Map<String, String>();
        Map<String, String> sourceBucketMap = new Map<String, String>();

        for (Bucket_Value__mdt cfg : [ SELECT Value__c, Value_Type__c, Bucket__c FROM Bucket_Value__mdt WHERE Active__c = true]) {
            if (cfg.Value_Type__c == 'Course' && courseValues.contains(cfg.Value__c)) {
                courseBucketMap.put(cfg.Value__c, cfg.Bucket__c);
            }
            if (cfg.Value_Type__c == 'Source' && sourceValues.contains(cfg.Value__c)) {
                sourceBucketMap.put(cfg.Value__c, cfg.Bucket__c);
            }
        }

        // Assign BOTH buckets
        for (SObject sob : toProcess) {

            /* ---------------- COURSE BUCKET ---------------- */
            if (hasField(sob, 'Course__c') && hasField(sob, 'Course_Bucket__c')) {
                String course = (String)sob.get('Course__c');
                String courseBucket = courseBucketMap.get(course);
                sob.put(
                    'Course_Bucket__c',
                    String.isBlank(courseBucket) ? 'NA' : courseBucket
                );
            }

            /* ---------------- SOURCE BUCKET ---------------- */
            if (hasField(sob, 'Source_Bucket__c')) {
                String sourceVal;

                if (hasField(sob, 'Source__c')) {
                    sourceVal = (String)sob.get('Source__c');
                }
                else if (sob.getSObjectType() == Lead.SObjectType) {
                    sourceVal = (String)sob.get('Coming_From__c');
                }

                String sourceBucket = sourceBucketMap.get(sourceVal);
                sob.put(
                    'Source_Bucket__c',
                    String.isBlank(sourceBucket) ? 'NA' : sourceBucket
                );
            }
        }
    }

    // Utility
    private static Boolean hasField(SObject sob, String fieldName) {
        return sob.getSObjectType()
                  .getDescribe()
                  .fields
                  .getMap()
                  .containsKey(fieldName);
    }
}