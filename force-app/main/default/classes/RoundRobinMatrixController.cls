/*
    Author       : ROHIT SINGH BISHT
    Description  :
*/
public without sharing class RoundRobinMatrixController {

    public class FilterInit {
        @AuraEnabled public List<String> cities;
        @AuraEnabled public List<String> leadSources; // holds Bucket values
    }

    public class Cell {
        @AuraEnabled public String poolId;
        @AuraEnabled public Integer assignedWeight;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Integer sequence;
    }

    public class Row {
        @AuraEnabled public String salesRepId;
        @AuraEnabled public String salesRepName;
        @AuraEnabled public Map<String, Cell> byLeadSource; // key = Bucket
    }

    public class MatrixResult {
        @AuraEnabled public Integer totalRows;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public List<String> columnsLeadSources; // Bucket columns
        @AuraEnabled public List<Row> rows;
    }

    public class WeightUpdate {
        @AuraEnabled public String poolId;
        @AuraEnabled public Decimal assignedWeight;
    }

    public class SeqUpdateDTO {
        @AuraEnabled public Id poolId;
        @AuraEnabled public Integer sequence;
    }

    public class SeqPayload {
        @AuraEnabled public String leadSource; // holds Bucket
        @AuraEnabled public String city;
        @AuraEnabled public List<SeqUpdateDTO> updates;
    }

    /* ================= FILTERS ================= */

    @AuraEnabled(cacheable=true)
    public static FilterInit getFilters(String objectApiName) {
        if (String.isBlank(objectApiName)) return new FilterInit();

        Set<String> cities = new Set<String>();
        Set<String> srcs = new Set<String>();

        for (Round_Robin_Pool__c p : [
            SELECT City__c, Bucket__c , Course__c,Sales_Rep__c,Sequence__c
            FROM Round_Robin_Pool__c
            WHERE Active__c = true
            AND Object_Api_Name__c = :objectApiName
        ]) {
            if (!String.isBlank(p.City__c)) cities.add(p.City__c);
            if (!String.isBlank(p.Bucket__c)) srcs.add(p.Bucket__c);
        }

        FilterInit f = new FilterInit();
        f.cities = new List<String>(cities);
        f.cities.sort();
        f.leadSources = new List<String>(srcs);
        f.leadSources.sort();
        return f;
    }

    /* ================= MATRIX ================= */

    @AuraEnabled(cacheable=true)
    public static MatrixResult getMatrix(
        String objectApiName,
        String city,
        List<String> leadSources,
        Integer pageNumber,
        Integer pageSize
    ) {
        if (pageNumber == null || pageNumber < 1) pageNumber = 1;
        if (pageSize == null || pageSize < 1) pageSize = 10;

        List<Round_Robin_Pool__c> poolList;
        if (leadSources == null || leadSources.isEmpty()) {
            poolList = [
                SELECT Id, Bucket__c, Sales_Rep__c,Course__c, Assigned_Weight__c, Active__c, Sequence__c
                FROM Round_Robin_Pool__c
                WHERE Active__c = true
                AND Object_Api_Name__c = :objectApiName
                AND City__c = :city
            ];
        } else {
            poolList = [
                SELECT Id, Bucket__c,Course__c, Sales_Rep__c, Assigned_Weight__c, Active__c, Sequence__c
                FROM Round_Robin_Pool__c
                WHERE Active__c = true
                AND Object_Api_Name__c = :objectApiName
                AND City__c = :city
                AND Bucket__c IN :leadSources
            ];
        }

        Set<Id> repIds = new Set<Id>();
        Set<String> srcs = new Set<String>();
        for (Round_Robin_Pool__c p : poolList) {
            if (p.Sales_Rep__c != null) repIds.add(p.Sales_Rep__c);
            if (!String.isBlank(p.Bucket__c)) srcs.add(p.Bucket__c);
        }

        List<String> columns = new List<String>(srcs);
        columns.sort();

        Map<Id, User> repMap = repIds.isEmpty()
            ? new Map<Id, User>()
            : new Map<Id, User>([
                SELECT Id, Name FROM User WHERE Id IN :repIds
            ]);

        Map<Id, Map<String, Round_Robin_Pool__c>> byRep = new Map<Id, Map<String, Round_Robin_Pool__c>>();
        for (Round_Robin_Pool__c p : poolList) {
            if (p.Sales_Rep__c == null || String.isBlank(p.Bucket__c)) continue;
            if (!byRep.containsKey(p.Sales_Rep__c)) {
                byRep.put(p.Sales_Rep__c, new Map<String, Round_Robin_Pool__c>());
            }
            byRep.get(p.Sales_Rep__c).put(p.Bucket__c, p);
        }

        List<Row> allRows = new List<Row>();
        for (Id repId : byRep.keySet()) {
            Row r = new Row();
            r.salesRepId = (String)repId;
            r.salesRepName = repMap.containsKey(repId) ? repMap.get(repId).Name : String.valueOf(repId);
            r.byLeadSource = new Map<String, Cell>();

            for (String s : columns) {
                Round_Robin_Pool__c p = byRep.get(repId).get(s);
                if (p == null) continue;

                Cell c = new Cell();
                c.poolId = p.Id;
                c.assignedWeight = (p.Assigned_Weight__c == null ? null : Integer.valueOf(p.Assigned_Weight__c));
                c.active = p.Active__c;
                c.sequence = (p.Sequence__c == null ? null : Integer.valueOf(p.Sequence__c));
                r.byLeadSource.put(s, c);
            }
            allRows.add(r);
        }

        allRows = sortRowsByName(allRows);

        Integer total = allRows.size();
        Integer fromIdx = Math.max(0, (pageNumber - 1) * pageSize);
        Integer toIdx = Math.min(total, fromIdx + pageSize);

        List<Row> pageRows = new List<Row>();
        for (Integer i = fromIdx; i < toIdx; i++) {
            pageRows.add(allRows[i]);
        }

        MatrixResult res = new MatrixResult();
        res.totalRows = total;
        res.pageNumber = pageNumber;
        res.pageSize = pageSize;
        res.columnsLeadSources = columns;
        res.rows = pageRows;
        return res;
    }

    private static List<Row> sortRowsByName(List<Row> input) {
        for (Integer i = 0; i < input.size(); i++) {
            for (Integer j = i + 1; j < input.size(); j++) {
                String a = input[i].salesRepName == null ? '' : input[i].salesRepName.toLowerCase();
                String b = input[j].salesRepName == null ? '' : input[j].salesRepName.toLowerCase();
                if (a > b) {
                    Row tmp = input[i];
                    input[i] = input[j];
                    input[j] = tmp;
                }
            }
        }
        return input;
    }

    /* ================= WEIGHTS ================= */

    @AuraEnabled
    public static void saveAssignedWeights(String updatesJson) {
        if (String.isBlank(updatesJson)) return;
        List<WeightUpdate> updates = (List<WeightUpdate>)JSON.deserialize(updatesJson, List<WeightUpdate>.class);
        applyUpdates(updates);
    }

    public static void applyUpdates(List<WeightUpdate> updates) {
        if (updates == null || updates.isEmpty()) return;

        Set<Id> ids = new Set<Id>();
        for (WeightUpdate u : updates) {
            if (String.isBlank(u.poolId)) continue;
            if (u.assignedWeight != null && u.assignedWeight < 0) {
                throw new AuraHandledException('Assigned Weight cannot be negative.');
            }
            ids.add((Id)u.poolId);
        }

        if (ids.isEmpty()) return;

        Map<Id, Round_Robin_Pool__c> mapPools =
            new Map<Id, Round_Robin_Pool__c>(
                [SELECT Id, Assigned_Weight__c FROM Round_Robin_Pool__c WHERE Id IN :ids]
            );

        List<Round_Robin_Pool__c> toUpdate = new List<Round_Robin_Pool__c>();
        for (WeightUpdate u : updates) {
            if (!mapPools.containsKey((Id)u.poolId)) continue;
            mapPools.get((Id)u.poolId).Assigned_Weight__c = u.assignedWeight;
            toUpdate.add(mapPools.get((Id)u.poolId));
        }
        if (!toUpdate.isEmpty()) update toUpdate;
    }

    /* ================= SEQUENCES ================= */

    @AuraEnabled
    public static void saveSequences(String updatesJson) {
        if (String.isBlank(updatesJson)) {
            throw new AuraHandledException('updatesJson is required.');
        }

        SeqPayload p = (SeqPayload)JSON.deserialize(updatesJson, SeqPayload.class);
        if (p == null || p.updates == null || p.updates.isEmpty()) {
            throw new AuraHandledException('No sequence updates provided.');
        }
        if (String.isBlank(p.leadSource)) {
            throw new AuraHandledException('leadSource is required.');
        }

        Set<Id> ids = new Set<Id>();
        Set<Integer> seen = new Set<Integer>();
        for (SeqUpdateDTO u : p.updates) {
            if (u.poolId == null || u.sequence == null || u.sequence < 1) {
                throw new AuraHandledException('Invalid sequence data.');
            }
            if (!seen.add(u.sequence)) {
                throw new AuraHandledException('Sequence values must be unique within this bucket.');
            }
            ids.add(u.poolId);
        }

        Map<Id, Round_Robin_Pool__c> targetMap =
            new Map<Id, Round_Robin_Pool__c>(
                [SELECT Id, Bucket__c, City__c,Course__c FROM Round_Robin_Pool__c WHERE Id IN :ids]
            );

        for (Round_Robin_Pool__c r : targetMap.values()) {
            if (r.Bucket__c != p.leadSource) {
                throw new AuraHandledException('All updates must belong to the same Bucket.');
            }
            if (p.city != null && p.city != r.City__c) {
                throw new AuraHandledException('All updates must belong to the selected City.');
            }
        }

        List<Round_Robin_Pool__c> peerList =
            p.city == null
                ? [SELECT Id, Sequence__c FROM Round_Robin_Pool__c WHERE Bucket__c = :p.leadSource]
                : [SELECT Id, Sequence__c FROM Round_Robin_Pool__c WHERE Bucket__c = :p.leadSource AND City__c = :p.city];

        Set<Integer> used = new Set<Integer>();
        for (Round_Robin_Pool__c peer : peerList) {
            if (!ids.contains(peer.Id) && peer.Sequence__c != null) {
                used.add(Integer.valueOf(peer.Sequence__c));
            }
        }

        for (SeqUpdateDTO u : p.updates) {
            if (used.contains(u.sequence)) {
                throw new AuraHandledException('Sequence ' + u.sequence + ' is already used in this bucket.');
            }
        }

        List<Round_Robin_Pool__c> toUpdate = new List<Round_Robin_Pool__c>();
        for (SeqUpdateDTO u : p.updates) {
            toUpdate.add(new Round_Robin_Pool__c(Id = u.poolId, Sequence__c = u.sequence));
        }
        update toUpdate;
    }
}