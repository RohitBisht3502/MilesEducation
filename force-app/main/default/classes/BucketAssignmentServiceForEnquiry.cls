public class BucketAssignmentServiceForEnquiry {
    
    public static void assignBucket(List<SObject> newList, Map<Id, SObject> oldMap) {
        if (newList == null || newList.isEmpty()) return;

        List<SObject> toProcess = new List<SObject>();

        Set<String> sourceValues = new Set<String>();

        // Detect changes
        for (SObject newRec : newList) {

            if (oldMap == null) {
                toProcess.add(newRec); // INSERT
            } else { // Update
                SObject oldRec = oldMap.get((Id)newRec.get('Id'));
                if (oldRec == null) continue;

                Boolean sourceChanged =
                    (hasField(newRec, 'Coming_From__c') &&
                     newRec.get('Coming_From__c') != oldRec.get('Coming_From__c'));

                if (sourceChanged) {
                    toProcess.add(newRec);
                }
            }
        }

        if (toProcess.isEmpty()) return;

        //  Collect values
        for (SObject sob : toProcess) {


            if (hasField(sob, 'Coming_From__c')) {
                String s = (String)sob.get('Coming_From__c');
                if (String.isNotBlank(s)) sourceValues.add(s);
            }
            
        }

        Map<String, String> sourceBucketMap = SourceBucketUtility.getBucketMapForValues(sourceValues, 'Source');

        // Assign BOTH buckets
        for (SObject sob : toProcess) {            

            /* ---------------- SOURCE BUCKET ---------------- */
            if (hasField(sob, 'Source_Bucket__c')) {
                String sourceVal;

                if (hasField(sob, 'Coming_From__c')) {
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