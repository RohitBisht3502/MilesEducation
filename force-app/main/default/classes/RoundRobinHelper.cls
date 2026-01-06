/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class RoundRobinHelper {
    public class BucketRef { public String objectApiName; public String cityUpper; public String sourceUpper; public String courseUpper; public String typeValue; }

    public static String normCity(String v)   { return String.isBlank(v) ? '(NONE)' : v.trim().toUpperCase(); }
    public static String normSource(String v) { return String.isBlank(v) ? '(NONE)' : v.trim().toUpperCase(); }
    public static String normCourse(String v) { return String.isBlank(v) ? '(ANY)'  : v.trim().toUpperCase(); }

    public static String keyOf(String obj, String cityUpper, String sourceUpper, String courseUpper, String typeValue) {
        String coursePart = String.isBlank(courseUpper) ? '(ANY)' : courseUpper;
        String srcPart    = String.isBlank(sourceUpper) ? '(NONE)' : sourceUpper;
        String typePart   = String.isBlank(typeValue)   ? 'Round Robin' : typeValue;
        return obj + '|' + cityUpper + '|' + srcPart + '|' + coursePart + '|' + typePart;
    }

    public static BucketRef bucketFromKey(String key) {
        List<String> parts = key.split('\\|');
        BucketRef b = new BucketRef();
        b.objectApiName = parts.size() > 0 ? parts[0] : '';
        b.cityUpper     = parts.size() > 1 ? parts[1] : '(NONE)';
        b.sourceUpper   = parts.size() > 2 ? parts[2] : '(NONE)';
        b.courseUpper   = parts.size() > 3 ? parts[3] : '(ANY)';
        b.typeValue     = parts.size() > 4 ? parts[4] : 'Round Robin';
        return b;
    }

    public static List<Round_Robin_Pool__c> lockPoolMembers(String obj, String cityUpper, String sourceUpper, String courseUpper, String typeValue) {
        Boolean ignoreSource = (typeValue != null && typeValue.equalsIgnoreCase('Eligibility Criteria'));
        List<Round_Robin_Pool__c> rows = q(obj, cityUpper, sourceUpper, courseUpper, typeValue, ignoreSource);
        sortBySequenceThenId(rows);
        return rows;
    }

    public static List<Round_Robin_Pool__c> q(String obj, String city, String src, String courseUpper, String typeValue, Boolean ignoreSource) {
        if (ignoreSource) {
            return [
                SELECT Id, Name, Object_Api_Name__c, City__c, Bucket__c,
                       Sales_Rep__c, Sequence__c, Max_Weight__c, Assigned_Weight__c,
                       Max_Leads__c, Total_Assigned__c, Maximum_Weightage__c,
                       Current_Assigned_Weight__c, Active__c, Course__c,Course_Bucket__c, Type__c
                FROM Round_Robin_Pool__c
                WHERE Active__c = true
                  AND Object_Api_Name__c = :obj
                  AND City__c = :city
                  AND Course_Bucket__c = :courseUpper
                  AND Type__c = :typeValue
                FOR UPDATE
            ];
        } else {
            return [
                SELECT Id, Name, Object_Api_Name__c, City__c, Bucket__c,Lead_Source__c,
                       Sales_Rep__c, Sequence__c, Max_Weight__c, Assigned_Weight__c,
                       Max_Leads__c, Total_Assigned__c, Maximum_Weightage__c,
                       Current_Assigned_Weight__c, Active__c, Course__c,Course_Bucket__c, Type__c
                FROM Round_Robin_Pool__c
                WHERE Active__c = true
                  AND Object_Api_Name__c = :obj
                  AND City__c = :city
                  AND Course_Bucket__c = :courseUpper
                  AND Type__c = :typeValue
                  AND Lead_Source__c = :src
                FOR UPDATE
            ];
        }
    }

    public static void sortBySequenceThenId(List<Round_Robin_Pool__c> rows) { rows.sort(new RRMemberComparator()); }

    public class RRMemberComparator implements System.Comparator<Round_Robin_Pool__c> {
        public Integer compare(Round_Robin_Pool__c a, Round_Robin_Pool__c b) {
            Decimal sa = (a.Sequence__c == null) ? 0 : a.Sequence__c;
            Decimal sb = (b.Sequence__c == null) ? 0 : b.Sequence__c;
            if (sa == sb) return String.valueOf(a.Id).compareTo(String.valueOf(b.Id));
            return (sa < sb) ? -1 : 1;
        }
    }

    public class PickResult { public Round_Robin_Pool__c member; public Boolean cycleReset; }

    public static PickResult pickNext(List<Round_Robin_Pool__c> pool, Id lastOwnerId) {
        PickResult r = new PickResult();
        r.cycleReset = false;

        Boolean allActiveMaxedNow = true;
        if (pool != null) {
            for (Round_Robin_Pool__c p : pool) {
                Integer weight = (p.Assigned_Weight__c == null) ? 0 : p.Assigned_Weight__c.intValue();
                Integer used   = (p.Current_Assigned_Weight__c == null) ? 0 : p.Current_Assigned_Weight__c.intValue();
                if (weight > 0) {
                    Boolean maxedOnLeads = (p.Max_Leads__c != null && p.Total_Assigned__c != null && p.Total_Assigned__c >= p.Max_Leads__c);
                    if (used < weight && !maxedOnLeads) { allActiveMaxedNow = false; break; }
                }
            }
        }

        if (allActiveMaxedNow) {
            System.debug(LoggingLevel.INFO, 'RoundRobinHelper.pickNext: cycle reset, poolSize=' + (pool == null ? 0 : pool.size()));
            resetCycle(pool);
            r.cycleReset = true;
            r.member = findEligible(pool, null, false);
            return r;
        }

        Round_Robin_Pool__c m = findEligible(pool, lastOwnerId, true);
        if (m != null) { r.member = m; return r; }

        m = findEligible(pool, lastOwnerId, false);
        if (m != null) { r.member = m; return r; }

        System.debug(LoggingLevel.INFO, 'RoundRobinHelper.pickNext: no eligible member, poolSize=' + (pool == null ? 0 : pool.size()) + ', lastOwnerId=' + String.valueOf(lastOwnerId));
        r.member = null;
        return r;
    }

    public static Round_Robin_Pool__c findEligible(List<Round_Robin_Pool__c> pool, Id lastOwnerId, Boolean avoidSame) {
        if (pool == null || pool.isEmpty()) return null;

        Integer startIndex = 0;
        if (lastOwnerId != null) {
            for (Integer i = 0; i < pool.size(); i++) {
                if (pool[i].Sales_Rep__c == lastOwnerId) {
                    startIndex = Math.mod(i + 1, pool.size());
                    break;
                }
            }
        }

        for (Integer i = 0; i < pool.size(); i++) {
            Integer currentIndex = Math.mod(startIndex + i, pool.size());
            Round_Robin_Pool__c p = pool[currentIndex];

            Integer weight = (p.Assigned_Weight__c == null) ? 0 : p.Assigned_Weight__c.intValue();
            Integer used   = (p.Current_Assigned_Weight__c == null) ? 0 : p.Current_Assigned_Weight__c.intValue();

            if (weight <= 0) continue;
            if (p.Max_Leads__c != null && p.Total_Assigned__c != null && p.Total_Assigned__c >= p.Max_Leads__c) continue;
            if (used >= weight) continue;
            if (avoidSame && lastOwnerId != null && p.Sales_Rep__c == lastOwnerId) continue;

            return p;
        }

        return null;
    }

    public static void resetCycle(List<Round_Robin_Pool__c> pool) {
        for (Round_Robin_Pool__c p : pool) p.Current_Assigned_Weight__c = 0;
    }

    public static void consumeSlot(Round_Robin_Pool__c p) {
        Integer used = (Integer)(p.Current_Assigned_Weight__c == null ? 0 : p.Current_Assigned_Weight__c.intValue());
        p.Current_Assigned_Weight__c = used + 1;
        Integer total = (Integer)(p.Total_Assigned__c == null ? 0 : p.Total_Assigned__c.intValue());
        p.Total_Assigned__c = total + 1;
    }
}