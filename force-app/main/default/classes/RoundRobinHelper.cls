public without sharing class RoundRobinHelper {
    public class BucketRef { public String objectApiName; public String cityUpper; public String sourceUpper; }

    public static String normCity(String v) { return String.isBlank(v) ? '(NONE)' : v.trim().toUpperCase(); }
    public static String normSource(String v) { return String.isBlank(v) ? '(NONE)' : v.trim().toUpperCase(); }
    public static String keyOf(String obj, String cityUpper, String sourceUpper) { return obj + '|' + cityUpper + '|' + sourceUpper; }

    public static BucketRef bucketFromKey(String key) {
        List<String> parts = key.split('\\|');
        BucketRef b = new BucketRef();
        b.objectApiName = parts.size() > 0 ? parts[0] : '';
        b.cityUpper     = parts.size() > 1 ? parts[1] : '(NONE)';
        b.sourceUpper   = parts.size() > 2 ? parts[2] : '(NONE)';
        return b;
    }

    public static List<Round_Robin_Pool__c> lockPoolMembers(String obj, String cityUpper, String sourceUpper) {
        List<Round_Robin_Pool__c> rows = q(obj, cityUpper, sourceUpper);
        sortBySequenceThenId(rows);
        return rows;
    }

    private static List<Round_Robin_Pool__c> q(String obj, String city, String src) {
        return [
            SELECT Id, Name, Object_Api_Name__c, City__c, Lead_Source__c, Sales_Rep__c, Sequence__c, Max_Weight__c, Assigned_Weight__c, Max_Leads__c, Total_Assigned__c, Maximum_Weightage__c, Current_Assigned_Weight__c, Active__c
            FROM Round_Robin_Pool__c
            WHERE Active__c = true
              AND Object_Api_Name__c = :obj
              AND City__c = :city
              AND Lead_Source__c = :src
            FOR UPDATE
        ];
    }

    private static void sortBySequenceThenId(List<Round_Robin_Pool__c> rows) { rows.sort(new RRMemberComparator()); }

    private class RRMemberComparator implements System.Comparator<Round_Robin_Pool__c> {
        public Integer compare(Round_Robin_Pool__c a, Round_Robin_Pool__c b) {
            Decimal sa = (a.Sequence__c == null) ? 0 : a.Sequence__c;
            Decimal sb = (b.Sequence__c == null) ? 0 : b.Sequence__c;
            if (sa == sb) return String.valueOf(a.Id).compareTo(String.valueOf(b.Id));
            return (sa < sb) ? -1 : 1;
        }
    }

    public class PickResult { public Round_Robin_Pool__c member; public Boolean cycleReset; }

    // public static PickResult pickNext(List<Round_Robin_Pool__c> pool, Id lastOwnerId) {
    //     PickResult r = new PickResult(); r.cycleReset = false;
    //     Round_Robin_Pool__c m = findEligible(pool, lastOwnerId, true);
    //     if (m != null) { r.member = m; return r; }
    //     m = findEligible(pool, lastOwnerId, false);
    //     if (m != null) { r.member = m; return r; }
    //     resetCycle(pool); r.cycleReset = true;
    //     m = (pool, lastOwnerId, true);
    //     if (m == findEligiblenull) m = findEligible(pool, lastOwnerId, false);
    //     r.member = m;
    //     return r;
    // }

    // public static PickResult pickNext(List<Round_Robin_Pool__c> pool) { return pickNext(pool, null); }

    // private static Round_Robin_Pool__c findEligible(List<Round_Robin_Pool__c> pool, Id lastOwnerId, Boolean avoidSame) {
    //     for (Round_Robin_Pool__c p : pool) {
    //         Integer weight = (Integer)(p.Assigned_Weight__c == null ? 0 : p.Assigned_Weight__c.intValue());
    //         Integer used   = (Integer)(p.Current_Assigned_Weight__c == null ? 0 : p.Current_Assigned_Weight__c.intValue());
    //         if (weight <= 0) continue;
    //         if (p.Max_Leads__c != null && p.Total_Assigned__c != null && p.Total_Assigned__c >= p.Max_Leads__c) continue;
    //         if (used >= weight) continue;
    //         if (avoidSame && lastOwnerId != null && p.Sales_Rep__c == lastOwnerId) continue;
    //         return p;
    //     }
    //     return null;
    // }
    public static PickResult pickNext(List<Round_Robin_Pool__c> pool, Id lastOwnerId) {
        System.debug('>>> pickNext START | pool size=' + (pool != null ? pool.size() : 0) + ' | lastOwnerId=' + lastOwnerId);

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
            System.debug('>>> PRE-ASSIGN RESET: all active members maxed -> resetting cycle');
            resetCycle(pool);
            r.cycleReset = true;

            Round_Robin_Pool__c mAfterReset = findEligible(pool, null, false);
            System.debug('>>> After reset eligible from start: ' + mAfterReset);
            r.member = mAfterReset;
            System.debug('>>> pickNext END | cycleReset=' + r.cycleReset + ' | member=' + (r.member != null ? r.member.Sales_Rep__c : null));
            return r;
        }

        Round_Robin_Pool__c m = findEligible(pool, lastOwnerId, true);
        System.debug('>>> First eligible (avoidSame=true): ' + m);
        if (m != null) { 
            r.member = m; 
            System.debug('>>> Returning member: ' + m.Id + ' | Sales Rep=' + m.Sales_Rep__c + ' | cycleReset=' + r.cycleReset);
            return r; 
        }

        m = findEligible(pool, lastOwnerId, false);
        System.debug('>>> Second eligible (avoidSame=false): ' + m);
        if (m != null) { 
            r.member = m; 
            System.debug('>>> Returning member: ' + m.Id + ' | Sales Rep=' + m.Sales_Rep__c + ' | cycleReset=' + r.cycleReset);
            return r; 
        }

        r.member = null;
        System.debug('>>> pickNext END | cycleReset=' + r.cycleReset + ' | member=' + null);
        return r;
    }
    public static PickResult pickNext(List<Round_Robin_Pool__c> pool) { 
        System.debug('>>> pickNext without lastOwnerId called');
        return pickNext(pool, null); 
    }
    private static Round_Robin_Pool__c findEligible(List<Round_Robin_Pool__c> pool, Id lastOwnerId, Boolean avoidSame) {
        System.debug('>>> findEligible START | avoidSame=' + avoidSame + ' | lastOwnerId=' + lastOwnerId);

        if (pool == null || pool.isEmpty()) {
            System.debug('>>> findEligible END | Pool is null/empty');
            return null;
        }

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

            System.debug('>>> Checking member=' + p.Id + ' | Rep=' + p.Sales_Rep__c +
                        ' | weight=' + weight + ' | used=' + used +
                        ' | maxLeads=' + p.Max_Leads__c + ' | totalAssigned=' + p.Total_Assigned__c);

            if (weight <= 0) { System.debug('... Skipped: weight <= 0'); continue; }
            if (p.Max_Leads__c != null && p.Total_Assigned__c != null && p.Total_Assigned__c >= p.Max_Leads__c) { System.debug('... Skipped: reached max leads'); continue; }
            if (used >= weight) { System.debug('... Skipped: used >= weight'); continue; }
            if (avoidSame && lastOwnerId != null && p.Sales_Rep__c == lastOwnerId) { System.debug('... Skipped: same as last owner'); continue; }

            System.debug('>>> Found eligible member=' + p.Id + ' | Sales_Rep=' + p.Sales_Rep__c);
            return p;
        }

        System.debug('>>> findEligible END | No eligible member found');
        return null;
    }

    private static void resetCycle(List<Round_Robin_Pool__c> pool) {
        for (Round_Robin_Pool__c p : pool) p.Current_Assigned_Weight__c = 0;
    }

    public static void consumeSlot(Round_Robin_Pool__c p) {
        Integer used = (Integer)(p.Current_Assigned_Weight__c == null ? 0 : p.Current_Assigned_Weight__c.intValue());
        p.Current_Assigned_Weight__c = used + 1;
        Integer total = (Integer)(p.Total_Assigned__c == null ? 0 : p.Total_Assigned__c.intValue());
        p.Total_Assigned__c = total + 1;
    }
}