public class SourceBucketUtility {

    public static Map<String, String> getBucketMapForValues(Set<String> targetValues, String valueType) {
        Map<String, String> valueToBucket = new Map<String, String>();
        if (targetValues == null || targetValues.isEmpty() || String.isBlank(valueType)) {
            return valueToBucket;
        }

        for (Bucket_Mapping__c mapping : getActiveMappings(valueType)) {
            for (String value : getConfiguredValues(mapping, valueType)) {
                if (targetValues.contains(value) && !valueToBucket.containsKey(value)) {
                    valueToBucket.put(value, mapping.Bucket__c);
                }
            }
        }
        return valueToBucket;
    }

    public static Map<String, Set<String>> getBucketToValues(String valueType) {
        Map<String, Set<String>> bucketToValues = new Map<String, Set<String>>();
        if (String.isBlank(valueType)) {
            return bucketToValues;
        }

        for (Bucket_Mapping__c mapping : getActiveMappings(valueType)) {
            if (!bucketToValues.containsKey(mapping.Bucket__c)) {
                bucketToValues.put(mapping.Bucket__c, new Set<String>());
            }
            bucketToValues.get(mapping.Bucket__c).addAll(getConfiguredValues(mapping, valueType));
        }
        return bucketToValues;
    }

    public static Set<String> getAllConfiguredValues(String valueType) {
        Set<String> values = new Set<String>();
        for (Set<String> configuredValues : getBucketToValues(valueType).values()) {
            values.addAll(configuredValues);
        }
        return values;
    }

    private static List<Bucket_Mapping__c> getActiveMappings(String valueType) {
        return [
            SELECT Bucket__c, Value_Type__c, Active__c, Sequence__c, Source_Values__c, Course_Values__c
            FROM Bucket_Mapping__c
            WHERE Active__c = true
            AND Value_Type__c = :valueType
            ORDER BY Sequence__c ASC, Bucket__c ASC
        ];
    }

    private static Set<String> getConfiguredValues(Bucket_Mapping__c mapping, String valueType) {
        Set<String> values = new Set<String>();
        if (mapping == null || String.isBlank(valueType)) {
            return values;
        }

        String rawValues = valueType == 'Course' ? mapping.Course_Values__c : mapping.Source_Values__c;
        if (String.isBlank(rawValues)) {
            return values;
        }

        for (String value : rawValues.split(';')) {
            String trimmedValue = value == null ? null : value.trim();
            if (String.isNotBlank(trimmedValue)) {
                values.add(trimmedValue);
            }
        }
        return values;
    }
}