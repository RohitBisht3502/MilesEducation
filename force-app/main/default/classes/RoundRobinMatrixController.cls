/*
    Author       : ROHIT SINGH BISHT
    Description  :
*/
public without sharing class RoundRobinMatrixController {
    private static final String TYPE_CC_PRE = 'CC - Pre Enrollment';
    private static final String TYPE_SR_POST = 'SR - Post Enrollment';
    private static final String TYPE_GP = 'GP';
    private static final String TYPE_MCOM = 'MCOM';
    private static final String PROFILE_CC = 'CC';
    private static final String PROFILE_SR = 'SR';
    private static final String PROFILE_GP = 'GP';
    private static final String PROFILE_MCOM = 'MCOM';

    public class FilterInit {
        @AuraEnabled public List<String> cities;
        @AuraEnabled public List<String> leadSources; 
        @AuraEnabled public List<String> buckets;
          @AuraEnabled public List<String> types;
          @AuraEnabled public List<String> roles;
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
        @AuraEnabled public Integer visibleUserCount;


        @AuraEnabled public Id salesRepId;
        @AuraEnabled public String city;
        @AuraEnabled public String bucket;
        @AuraEnabled public String leadSource;
        @AuraEnabled public String businessVertical;
@AuraEnabled public String course;
 @AuraEnabled public String typeVal;
 @AuraEnabled public String role;

        @AuraEnabled public String objectApiName;
    }

    public class SeqUpdateDTO {
        @AuraEnabled public Id poolId;
        @AuraEnabled public Integer sequence;
    }

    public class SeqPayload {
        @AuraEnabled public String leadSource; // holds Bucket
        @AuraEnabled public String city;
          @AuraEnabled public String bucket;
         @AuraEnabled public String businessVertical;
        @AuraEnabled public List<SeqUpdateDTO> updates;
          @AuraEnabled public String typeVal;
          @AuraEnabled public String role;
    }

    /* ================= FILTERS ================= */

@AuraEnabled(cacheable=true)
public static Map<String, Object> getBucketConfiguration(String type) {
    Map<String, Object> result = new Map<String, Object>();

    List<Bucket_Value__mdt> bucketConfigs = [
        SELECT Value__c, Bucket__c, Value_Type__c
        FROM Bucket_Value__mdt
        WHERE Active__c = true
        AND Value_Type__c = :type
        ORDER BY Bucket__c, Value__c
    ];

    Map<String, Set<String>> bucketToSources = new Map<String, Set<String>>();
    Set<String> allSources = new Set<String>();
    Set<String> businessVerticals = new Set<String>(); 

    for (Bucket_Value__mdt config : bucketConfigs) {
        if (!bucketToSources.containsKey(config.Bucket__c)) {
            bucketToSources.put(config.Bucket__c, new Set<String>());
        }
        bucketToSources.get(config.Bucket__c).add(config.Value__c);
        allSources.add(config.Value__c);

        // // ✅ Example: if Value_Type__c == 'BusinessVertical'
        // if (config.Value_Type__c == 'BusinessVertical') {
        //     businessVerticals.add(config.Value__c);
        // }
    }

    result.put('buckets', new List<String>(bucketToSources.keySet()));
    result.put('bucketSourcesMap', bucketToSources);
    result.put('allSources', new List<String>(allSources));
    result.put('businessVerticals', new List<String>(businessVerticals)); // ✅ IMPORTANT

    return result;
}





private static String resolveObjectApiName(String typeVal) {
    if (String.isBlank(typeVal) || typeVal == TYPE_CC_PRE) {
        return 'Lead__c';
    }
    if (typeVal == TYPE_GP) {
        return 'Lead';
    }
    if (typeVal == TYPE_SR_POST) {
        return 'Course_Enrolled__c';
    }
    if (typeVal == TYPE_MCOM) {
        return 'Lead__c';
    }
    throw new AuraHandledException('Invalid Type selected: ' + typeVal);
}


@AuraEnabled(cacheable=true)
public static List<String> getBusinessVerticals() {
    Schema.DescribeFieldResult d =
        Round_Robin_Pool__c.Course_Bucket__c.getDescribe();

    List<String> vals = new List<String>();
    for (Schema.PicklistEntry p : d.getPicklistValues()) {
        if (p.isActive()) {
           vals.add(p.getValue());

        }
    }
    return vals;
}


   @AuraEnabled(cacheable=true)
public static FilterInit getFilters(String objectApiName) {
    if (String.isBlank(objectApiName)) return new FilterInit();

    List<String> cityVals = getValues(Round_Robin_Pool__c.City__c.getDescribe());
    cityVals.sort();
Map<String, Object> bucketConfig = getBucketConfiguration('Source');

    List<String> configuredBuckets = (List<String>)bucketConfig.get('buckets');
    configuredBuckets.sort();

    List<String> allSources = (List<String>)bucketConfig.get('allSources');
    allSources.sort();

    // ✅ ADD THIS
    List<String> typeVals =
        getValues(Round_Robin_Pool__c.Type__c.getDescribe());
    typeVals.sort();

    FilterInit f = new FilterInit();
    f.cities = cityVals;
    f.buckets = configuredBuckets;
    f.leadSources = allSources;
    f.types = typeVals;
     f.roles = new List<String>{ 'CC', 'SR' }; 

    return f;
}

  @AuraEnabled(cacheable=true)
public static MatrixResult getMatrix(
    String city,
    String bucket,
    List<String> leadSources,
    String businessVertical,
    String typeVal,
    String role,
    Integer pageNumber,
    Integer pageSize
) {
    String finalType = String.isBlank(typeVal)
        ? TYPE_CC_PRE
        : typeVal;
    if (String.isBlank(role) && TYPE_CC_PRE.equalsIgnoreCase(finalType)) {
        role = 'CC';
    }
    String objectApiName = resolveObjectApiNameByRoleAndType(role, finalType);
    Boolean cityWiseOnly = isCityWiseOnly(finalType, role);
    String profileName = resolveProfileNameByType(finalType);


    System.debug(
        'getMatrix :: INPUTS => city=' + city +
        ', bucket=' + bucket +
        ', businessVertical=' + businessVertical +
        ', type=' + finalType +
        ', objectApiName=' + objectApiName
    );

    if (pageNumber == null || pageNumber < 1) pageNumber = 1;
    if (pageSize == null || pageSize < 1) pageSize = 10;

        System.debug(LoggingLevel.DEBUG, 'getMatrix :: Normalized paging/objectApiName => pageNumber=' + pageNumber + ', pageSize=' + pageSize + ', objectApiName=' + objectApiName);

        Map<String, Object> bucketConfig = getBucketConfiguration('Source');
        System.debug(LoggingLevel.DEBUG, 'getMatrix :: bucketConfig keys => ' + (bucketConfig == null ? null : bucketConfig.keySet()));

        List<String> allSources = (List<String>)bucketConfig.get('allSources');
        if (allSources == null) allSources = new List<String>();
        allSources.sort();

        System.debug(LoggingLevel.DEBUG, 'getMatrix :: allSources (sorted) size=' + allSources.size() + ' => ' + allSources);

        List<String> columns = new List<String>();
        if (cityWiseOnly) {
            columns.add('City Wise');
        } else {
            if (leadSources != null && !leadSources.isEmpty()) {
                for (String src : leadSources) {
                    if (allSources.contains(src)) columns.add(src);
                }
            }
            if (columns.isEmpty()) columns.addAll(allSources);
            columns.sort();
        }

        System.debug(LoggingLevel.DEBUG, 'getMatrix :: columns (final) size=' + columns.size() + ' => ' + columns);

        List<User> reps;
     if (!String.isBlank(city)) {
    if (!String.isBlank(profileName)) {
        reps = [
            SELECT Id, Name, City__c, Profile.Name
            FROM User
            WHERE IsActive = true
            AND City__c = :city
            AND Profile.Name = :profileName
            ORDER BY Name
        ];
    } else if (!String.isBlank(role)) {
        reps = [
            SELECT Id, Name, City__c, UserRole.Name
            FROM User
            WHERE IsActive = true
            AND City__c = :city
            AND UserRole.Name = :role
            ORDER BY Name
        ];
    } else {
        reps = [
            SELECT Id, Name, City__c
            FROM User
            WHERE IsActive = true
            AND City__c = :city
            ORDER BY Name
        ];
    }





            System.debug(LoggingLevel.INFO, 'getMatrix :: reps fetched size=' + reps.size());
        } else {
            System.debug(LoggingLevel.WARN, 'getMatrix :: city is blank, returning empty result');
            MatrixResult emptyRes = new MatrixResult();
            emptyRes.totalRows = 0;
            emptyRes.pageNumber = pageNumber;
            emptyRes.pageSize = pageSize;
            emptyRes.columnsLeadSources = columns;
            emptyRes.rows = new List<Row>();
            System.debug(LoggingLevel.INFO, 'getMatrix :: END (empty) => totalRows=0');
            return emptyRes;
        }

        Set<Id> repIds = new Set<Id>();
        for (User u : reps) repIds.add(u.Id);
        System.debug(LoggingLevel.DEBUG, 'getMatrix :: repIds size=' + repIds.size());

        if (String.isBlank(typeVal)) {
            typeVal = TYPE_CC_PRE;
        }
        System.debug(LoggingLevel.DEBUG, 'getMatrix :: typeVal (final) => ' + typeVal);

       String q =
'SELECT Id, Bucket__c, Sales_Rep__c, Lead_Source__c, Assigned_Weight__c, Active__c, Sequence__c ' +
'FROM Round_Robin_Pool__c ' +
'WHERE Active__c = true ' +
'AND City__c = :city ' +
'AND Sales_Rep__c IN :repIds ';

if (!String.isBlank(typeVal)) {
    q += ' AND Type__c = :typeVal ';
}

if (!String.isBlank(objectApiName)) {
    q += ' AND Object_Api_Name__c = :objectApiName ';
}


        if (cityWiseOnly) {
            q += ' AND Lead_Source__c = NULL ';
            q += ' AND Bucket__c = NULL ';
            q += ' AND Course_Bucket__c = NULL ';
            q += ' ORDER BY Sequence__c ASC, Sales_Rep__r.Name';
        } else {
            if (!String.isBlank(bucket)) q += ' AND Bucket__c = :bucket ';
            if (!String.isBlank(businessVertical)) q += ' AND Course_Bucket__c = :businessVertical ';
            if (leadSources != null && !leadSources.isEmpty()) q += ' AND Lead_Source__c IN :leadSources ';
            q += ' ORDER BY Lead_Source__c, Sequence__c ASC, Sales_Rep__r.Name';
        }

        System.debug(LoggingLevel.DEBUG, 'getMatrix :: SOQL => ' + q);

        List<Round_Robin_Pool__c> poolList = Database.query(q);
        System.debug(LoggingLevel.INFO, 'getMatrix :: poolList fetched size=' + (poolList == null ? 0 : poolList.size()));

        Map<Id, Map<String, Round_Robin_Pool__c>> byRep = new Map<Id, Map<String, Round_Robin_Pool__c>>();
        Integer skipped = 0;
        for (Round_Robin_Pool__c p : poolList) {
            if (p.Sales_Rep__c == null) {
                skipped++;
                continue;
            }
            String sourceKey = cityWiseOnly ? 'City Wise' : p.Lead_Source__c;
            if (!cityWiseOnly && String.isBlank(sourceKey)) {
                skipped++;
                continue;
            }
            if (!byRep.containsKey(p.Sales_Rep__c)) byRep.put(p.Sales_Rep__c, new Map<String, Round_Robin_Pool__c>());
            byRep.get(p.Sales_Rep__c).put(sourceKey, p);
        }
        System.debug(LoggingLevel.DEBUG, 'getMatrix :: byRep repsMapped=' + byRep.size() + ', skippedPoolRows=' + skipped);

        List<Row> allRows = new List<Row>();
        Integer cellsWithRecord = 0;
        Integer cellsNull = 0;

        for (User u : reps) {
            Row r = new Row();
            r.salesRepId = u.Id;
            r.salesRepName = u.Name;
            r.byLeadSource = new Map<String, Cell>();

            for (String src : columns) {
                Round_Robin_Pool__c pool = (byRep.containsKey(u.Id) ? byRep.get(u.Id).get(src) : null);
                if (pool != null) {
                    Cell c = new Cell();
                    c.poolId = pool.Id;
                    c.assignedWeight = (pool.Assigned_Weight__c == null ? null : Integer.valueOf(pool.Assigned_Weight__c));
                    c.active = pool.Active__c;
                    c.sequence = (pool.Sequence__c == null ? null : Integer.valueOf(pool.Sequence__c));
                    r.byLeadSource.put(src, c);
                    cellsWithRecord++;
                } else {
                    r.byLeadSource.put(src, null);
                    cellsNull++;
                }
            }
            allRows.add(r);
        }

        System.debug(LoggingLevel.INFO, 'getMatrix :: allRows size=' + allRows.size() + ', cellsWithRecord=' + cellsWithRecord + ', cellsNull=' + cellsNull);

        Integer total = allRows.size();
        Integer fromIdx = Math.max(0, (pageNumber - 1) * pageSize);
        Integer toIdx = Math.min(total, fromIdx + pageSize);

        System.debug(LoggingLevel.DEBUG, 'getMatrix :: pagination => total=' + total + ', fromIdx=' + fromIdx + ', toIdx=' + toIdx);

        List<Row> pageRows = new List<Row>();
        for (Integer i = fromIdx; i < toIdx; i++) {
            pageRows.add(allRows[i]);
        }

        System.debug(LoggingLevel.INFO, 'getMatrix :: pageRows size=' + pageRows.size());

        MatrixResult res = new MatrixResult();
        res.totalRows = total;
        res.pageNumber = pageNumber;
        res.pageSize = pageSize;
        res.columnsLeadSources = columns;
        res.rows = pageRows;

        System.debug(LoggingLevel.INFO, 'getMatrix :: END => totalRows=' + res.totalRows + ', pageNumber=' + res.pageNumber + ', pageSize=' + res.pageSize
            + ', columns=' + (res.columnsLeadSources == null ? 0 : res.columnsLeadSources.size())
            + ', rows=' + (res.rows == null ? 0 : res.rows.size()));

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
/* ================= WEIGHTS ================= */

@AuraEnabled
public static void saveAssignedWeights(String updatesJson) {
    if (String.isBlank(updatesJson)) return;

    List<WeightUpdate> updates = (List<WeightUpdate>)JSON.deserialize(updatesJson, List<WeightUpdate>.class);
    applyUpdates(updates);
}


private static void validateLeadSourceTotals(List<WeightUpdate> updates) {
    if (updates == null || updates.isEmpty()) return;

    Map<String, List<WeightUpdate>> byContext = new Map<String, List<WeightUpdate>>();
    for (WeightUpdate w : updates) {
        if (String.isBlank(w.city) || String.isBlank(w.leadSource) || w.salesRepId == null) continue;

        String key =
            (w.city == null ? '' : w.city) + '|' +
            (w.bucket == null ? '' : w.bucket) + '|' +
            (w.businessVertical == null ? '' : w.businessVertical) + '|' +
            (String.isBlank(w.typeVal) ? TYPE_CC_PRE : w.typeVal) + '|' +
            resolveObjectApiNameByRoleAndType(w.role, w.typeVal) + '|' +
            w.leadSource;

        if (!byContext.containsKey(key)) {
            byContext.put(key, new List<WeightUpdate>());
        }
        byContext.get(key).add(w);
    }

    for (String ctx : byContext.keySet()) {
        List<WeightUpdate> groupedUpdates = byContext.get(ctx);
        WeightUpdate sample = groupedUpdates[0];

        String typeVal = String.isBlank(sample.typeVal) ? TYPE_CC_PRE : sample.typeVal;
        String objectApiName = resolveObjectApiNameByRoleAndType(sample.role, typeVal);

        List<Round_Robin_Pool__c> existing;
        if (String.isBlank(sample.businessVertical) && String.isBlank(sample.bucket)) {
            existing = [
                SELECT Sales_Rep__c, Assigned_Weight__c
                FROM Round_Robin_Pool__c
                WHERE Active__c = true
                  AND City__c = :sample.city
                  AND Lead_Source__c = :sample.leadSource
                  AND Type__c = :typeVal
                  AND Object_Api_Name__c = :objectApiName
                  AND Course_Bucket__c = NULL
                  AND Bucket__c = NULL
            ];
        } else if (String.isBlank(sample.businessVertical)) {
            existing = [
                SELECT Sales_Rep__c, Assigned_Weight__c
                FROM Round_Robin_Pool__c
                WHERE Active__c = true
                  AND City__c = :sample.city
                  AND Lead_Source__c = :sample.leadSource
                  AND Type__c = :typeVal
                  AND Object_Api_Name__c = :objectApiName
                  AND Course_Bucket__c = NULL
                  AND Bucket__c = :sample.bucket
            ];
        } else if (String.isBlank(sample.bucket)) {
            existing = [
                SELECT Sales_Rep__c, Assigned_Weight__c
                FROM Round_Robin_Pool__c
                WHERE Active__c = true
                  AND City__c = :sample.city
                  AND Lead_Source__c = :sample.leadSource
                  AND Type__c = :typeVal
                  AND Object_Api_Name__c = :objectApiName
                  AND Course_Bucket__c = :sample.businessVertical
                  AND Bucket__c = NULL
            ];
        } else {
            existing = [
                SELECT Sales_Rep__c, Assigned_Weight__c
                FROM Round_Robin_Pool__c
                WHERE Active__c = true
                  AND City__c = :sample.city
                  AND Lead_Source__c = :sample.leadSource
                  AND Type__c = :typeVal
                  AND Object_Api_Name__c = :objectApiName
                  AND Course_Bucket__c = :sample.businessVertical
                  AND Bucket__c = :sample.bucket
            ];
        }

        Map<Id, Integer> finalByRep = new Map<Id, Integer>();
        for (Round_Robin_Pool__c rr : existing) {
            if (rr.Sales_Rep__c == null) continue;
            finalByRep.put(rr.Sales_Rep__c, rr.Assigned_Weight__c == null ? 0 : Integer.valueOf(rr.Assigned_Weight__c));
        }

        Integer expected = 0;
        for (WeightUpdate w : groupedUpdates) {
            if (w.visibleUserCount != null && w.visibleUserCount > expected) {
                expected = w.visibleUserCount;
            }
            finalByRep.put(w.salesRepId, w.assignedWeight == null ? 0 : Integer.valueOf(w.assignedWeight));
        }

        if (expected <= 0) {
            expected = finalByRep.size();
        }

        Integer total = 0;
        for (Integer wt : finalByRep.values()) {
            total += wt;
        }

        if (total > expected) {
            throw new AuraHandledException(
                'Total assigned weight for Lead Source "' + sample.leadSource +
                '" cannot be greater than total Sales Reps (' +
                expected +
                '). Current total is ' + total + '.'
            );
        }
    }
}



@AuraEnabled
public static void applyUpdates(List<WeightUpdate> updates) {
    if (updates == null || updates.isEmpty()) return;

    // Validate basic weights
    for (WeightUpdate w : updates) {
        if (w.assignedWeight == null || w.assignedWeight < 0) {
            throw new AuraHandledException('Assigned Weight cannot be negative.');
        }
    }

    Set<Id> poolIds = new Set<Id>();
    Set<Id> salesRepIds = new Set<Id>();
    for (WeightUpdate w : updates) {
        if (w.poolId != null) poolIds.add(w.poolId);
        if (w.salesRepId != null) salesRepIds.add(w.salesRepId);
    }

    Map<Id, Round_Robin_Pool__c> existingById = new Map<Id, Round_Robin_Pool__c>();
    if (!poolIds.isEmpty()) {
        existingById = new Map<Id, Round_Robin_Pool__c>(
            [SELECT Id FROM Round_Robin_Pool__c WHERE Id IN :poolIds]
        );
    }

    List<Round_Robin_Pool__c> toInsert = new List<Round_Robin_Pool__c>();
    List<Round_Robin_Pool__c> toUpdate = new List<Round_Robin_Pool__c>();

    for (WeightUpdate w : updates) {
        Boolean cityWiseOnly = isCityWiseOnly(w.typeVal, w.role);
        String finalType = String.isBlank(w.typeVal) ? TYPE_CC_PRE : w.typeVal;

        if (w.poolId != null && existingById.containsKey(w.poolId)) {
            // Update existing record
            Round_Robin_Pool__c rr = existingById.get(w.poolId);
            rr.Assigned_Weight__c = w.assignedWeight;
            rr.Lead_Source__c = cityWiseOnly ? null : w.leadSource;
            rr.Bucket__c = cityWiseOnly ? null : w.bucket;
            rr.Course_Bucket__c = cityWiseOnly ? null : w.businessVertical;
            rr.Type__c = finalType;
            rr.Object_Api_Name__c = resolveObjectApiNameByRoleAndType(w.role, finalType);
            rr.Active__c = true;
            toUpdate.add(rr);
        } else {
            // Insert new record
            toInsert.add(new Round_Robin_Pool__c(
                Sales_Rep__c = w.salesRepId,
                Lead_Source__c = cityWiseOnly ? null : w.leadSource,
                City__c = w.city,
                Assigned_Weight__c = w.assignedWeight,
                Bucket__c = cityWiseOnly ? null : w.bucket,
                Course_Bucket__c = cityWiseOnly ? null : w.businessVertical,
                Type__c = finalType,
                Object_Api_Name__c = resolveObjectApiNameByRoleAndType(w.role, finalType),
                Active__c = true
            ));
        }
    }

 

    // Perform DML (totals are validated in UI)
    if (!toUpdate.isEmpty()) update toUpdate;
    if (!toInsert.isEmpty()) insert toInsert;
}

private static String resolveObjectApiNameByRole(String role) {
    return resolveObjectApiNameByRoleAndType(role, null);
}

private static String resolveObjectApiNameByRoleAndType(String role, String typeVal) {
    String finalType = String.isBlank(typeVal) ? null : typeVal;

    if (TYPE_GP.equalsIgnoreCase(finalType)) return 'Lead';
    if (TYPE_SR_POST.equalsIgnoreCase(finalType)) return 'Course_Enrolled__c';
    if (TYPE_MCOM.equalsIgnoreCase(finalType)) return 'Lead__c';
    if (TYPE_CC_PRE.equalsIgnoreCase(finalType)) return 'Lead__c';

    if (String.isBlank(role) || role == 'CC') return 'Lead__c';
    if (role == 'SR') return 'Course_Enrolled__c';
    throw new AuraHandledException('Invalid role: ' + role);
}

private static Boolean isCityWiseOnly(String typeVal, String role) {
    String finalType = String.isBlank(typeVal) ? TYPE_CC_PRE : typeVal;

    if (TYPE_CC_PRE.equalsIgnoreCase(finalType)) return false;
    return true;
}

private static String resolveProfileNameByType(String typeVal) {
    if (TYPE_CC_PRE.equalsIgnoreCase(typeVal)) return PROFILE_CC;
    if (TYPE_SR_POST.equalsIgnoreCase(typeVal)) return PROFILE_SR;
    if (TYPE_GP.equalsIgnoreCase(typeVal)) return PROFILE_GP;
    if (TYPE_MCOM.equalsIgnoreCase(typeVal)) return PROFILE_MCOM;
    return null;
}




    /* ================= SEQUENCES ================= */
@AuraEnabled
public static void saveSequences(String updatesJson) {

    System.debug('💡 saveSequences START');
    System.debug('💡 raw payload: ' + updatesJson);

    if (String.isBlank(updatesJson)) {
        System.debug('❌ updatesJson is blank');
        throw new AuraHandledException('updatesJson is required.');
    }

    /* ================================
       DEBUG: RAW JSON CHECK (SAFE)
       ================================ */
    try {
        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(updatesJson);

        System.debug('💡 parsed.leadSource        : ' + (String) parsed.get('leadSource'));
        System.debug('💡 parsed.city              : ' + (String) parsed.get('city'));
        System.debug('💡 parsed.bucket            : ' + (String) parsed.get('bucket'));
        System.debug('💡 parsed.businessVertical  : ' + (String) parsed.get('businessVertical'));
        System.debug('💡 parsed.typeVal           : ' + (String) parsed.get('typeVal'));
        System.debug('💡 parsed.updates (raw)     : ' + parsed.get('updates'));
    } catch (Exception ex) {
        System.debug('❌ JSON parsing error: ' + ex.getMessage());
        throw ex;
    }

    /* ================================
       STEP 0: DESERIALIZE STRONG TYPE
       ================================ */
    SeqPayload p = (SeqPayload) JSON.deserialize(updatesJson, SeqPayload.class);

    System.debug('💡 payload deserialized? ' + (p != null));
    if (p != null) {
        System.debug('💡 p.leadSource       : ' + p.leadSource);
        System.debug('💡 p.city             : ' + p.city);
        System.debug('💡 p.bucket           : ' + p.bucket);
        System.debug('💡 p.businessVertical : ' + p.businessVertical);
        System.debug('💡 p.typeVal          : ' + p.typeVal);
        System.debug('💡 p.updates.size     : ' + (p.updates == null ? 0 : p.updates.size()));
    }

    if (p == null || p.updates == null || p.updates.isEmpty()) {
        System.debug('❌ No sequence updates provided');
        throw new AuraHandledException('No sequence updates provided.');
    }

    String finalType = String.isBlank(p.typeVal) ? TYPE_CC_PRE : p.typeVal;
    Boolean cityWiseOnly = isCityWiseOnly(finalType, p.role);

    if (!cityWiseOnly && String.isBlank(p.leadSource)) {
        System.debug('❌ leadSource missing');
        throw new AuraHandledException('leadSource is required.');
    }

    /* ================================
       STEP 1: BASIC VALIDATION
       ================================ */
    Set<Id> ids = new Set<Id>();
    Set<Integer> seen = new Set<Integer>();

    for (SeqUpdateDTO u : p.updates) {
        System.debug('💡 incoming update -> poolId=' + u.poolId + ', sequence=' + u.sequence);

        if (u.poolId == null || u.sequence == null || u.sequence < 1) {
            System.debug('❌ Invalid sequence data found in updates');
            throw new AuraHandledException('Invalid sequence data.');
        }

        if (!seen.add(u.sequence)) {
            System.debug('❌ Duplicate sequence detected: ' + u.sequence);
            throw new AuraHandledException('Sequence values must be unique within this bucket.');
        }

        ids.add(u.poolId);
    }

    System.debug('💡 validated updates: count=' + p.updates.size() + ', uniquePoolIds=' + ids.size());

    /* ================================
       STEP 2: RESOLVE CONTEXT
       ================================ */
    String objectApiName = resolveObjectApiNameByRoleAndType(p.role, finalType);

    System.debug('resolved context -> finalType=' + finalType + ', role=' + p.role + ', cityWiseOnly=' + cityWiseOnly + ', objectApiName=' + objectApiName);

    /* ================================
       STEP 3: FETCH TARGET RECORDS
       ================================ */
    Map<Id, Round_Robin_Pool__c> targetMap =
        new Map<Id, Round_Robin_Pool__c>([
            SELECT Id,
                   Bucket__c,
                   Lead_Source__c,
                   City__c,
                   Course_Bucket__c,
                   Sequence__c,
                   Type__c,
                   Object_Api_Name__c,
                   Active__c
            FROM Round_Robin_Pool__c
            WHERE Id IN :ids
        ]);

    System.debug('💡 target records fetched: ' + targetMap.size());

    if (targetMap.size() != ids.size()) {
        System.debug('❌ Some records not found. expected=' + ids.size() + ', got=' + targetMap.size());
        throw new AuraHandledException('Some records were not found. Please reload and try again.');
    }

    /* ================================
       STEP 4: CONTEXT CONSISTENCY CHECK
       (NULL-SAFE, JS-COMPATIBLE)
       ================================ */
    for (Round_Robin_Pool__c r : targetMap.values()) {

        // Helpful per-record tracing
        System.debug(
            '💡 target row -> Id=' + r.Id +
            ', Lead_Source__c=' + r.Lead_Source__c +
            ', City__c=' + r.City__c +
            ', Bucket__c=' + r.Bucket__c +
            ', Course_Bucket__c=' + r.Course_Bucket__c +
            ', Type__c=' + r.Type__c +
            ', Object_Api_Name__c=' + r.Object_Api_Name__c +
            ', Active__c=' + r.Active__c
        );

        if (!cityWiseOnly && r.Lead_Source__c != p.leadSource) {
            System.debug('❌ Lead Source mismatch: expected=' + p.leadSource + ', got=' + r.Lead_Source__c);
            throw new AuraHandledException('Lead Source mismatch detected.');
        }

        if (p.city != null && r.City__c != p.city) {
            System.debug('❌ City mismatch: expected=' + p.city + ', got=' + r.City__c);
            throw new AuraHandledException('City mismatch detected.');
        }

        if (!cityWiseOnly && p.bucket != null && r.Bucket__c != p.bucket) {
            System.debug('❌ Bucket mismatch: expected=' + p.bucket + ', got=' + r.Bucket__c);
            throw new AuraHandledException('Bucket mismatch detected.');
        }

        if (r.Type__c != finalType) {
            System.debug('❌ Type mismatch: expected=' + finalType + ', got=' + r.Type__c);
            throw new AuraHandledException('Type mismatch detected.');
        }

        if (r.Object_Api_Name__c != objectApiName) {
            System.debug('❌ Object API mismatch: expected=' + objectApiName + ', got=' + r.Object_Api_Name__c);
            throw new AuraHandledException('Object API mismatch detected.');
        }

        if (cityWiseOnly) {
            if (r.Lead_Source__c != null || r.Bucket__c != null || r.Course_Bucket__c != null) {
                throw new AuraHandledException('City-wise records must not have Lead Source, Bucket, or Business Vertical.');
            }
        } else {
            // NULL-SAFE BUSINESS VERTICAL CHECK
            if ((p.businessVertical != null || r.Course_Bucket__c != null) &&
                p.businessVertical != r.Course_Bucket__c) {

                System.debug(
                    '❌ Business Vertical mismatch: expected=' + p.businessVertical +
                    ', got=' + r.Course_Bucket__c
                );
                throw new AuraHandledException('Business Vertical mismatch detected.');
            }
        }
    }

    System.debug('💡 context consistency check: PASSED');

    /* ================================
       STEP 5: FETCH PEERS (FIXED NULL-SAFE FILTER)
       ================================ */
    System.debug(
        '💡 peer query filters -> leadSource=' + p.leadSource +
        ', city=' + p.city +
        ', bucket=' + p.bucket +
        ', businessVertical=' + p.businessVertical +
        ', finalType=' + finalType +
        ', objectApiName=' + objectApiName
    );

    List<Round_Robin_Pool__c> peerList;

    if (cityWiseOnly) {
        peerList = [
            SELECT Id, Sequence__c
            FROM Round_Robin_Pool__c
            WHERE City__c = :p.city
              AND Lead_Source__c = NULL
              AND Bucket__c = NULL
              AND Course_Bucket__c = NULL
              AND Type__c = :finalType
              AND Object_Api_Name__c = :objectApiName
              AND Active__c = true
        ];
    } else if (p.businessVertical == null) {
        // Course_Bucket__c filter must be NULL-SAFE; otherwise "Course_Bucket__c = null" returns no rows.
        peerList = [
            SELECT Id, Sequence__c
            FROM Round_Robin_Pool__c
            WHERE Lead_Source__c = :p.leadSource
              AND City__c = :p.city
              AND Bucket__c = :p.bucket
              AND Course_Bucket__c = NULL
              AND Type__c = :finalType
              AND Object_Api_Name__c = :objectApiName
              AND Active__c = true
        ];
    } else {
        peerList = [
            SELECT Id, Sequence__c
            FROM Round_Robin_Pool__c
            WHERE Lead_Source__c = :p.leadSource
              AND City__c = :p.city
              AND Bucket__c = :p.bucket
              AND Course_Bucket__c = :p.businessVertical
              AND Type__c = :finalType
              AND Object_Api_Name__c = :objectApiName
              AND Active__c = true
        ];
    }

    System.debug('💡 peers fetched: ' + peerList.size());

    /* ================================
       STEP 6: EXISTING SEQUENCE CHECK
       ================================ */
    Map<Integer, Id> existingSeqToId = new Map<Integer, Id>();

    for (Round_Robin_Pool__c peer : peerList) {
        if (!ids.contains(peer.Id) && peer.Sequence__c != null) {
            Integer seq = Integer.valueOf(peer.Sequence__c);
            existingSeqToId.put(seq, peer.Id);
            System.debug('💡 peer seq in use -> seq=' + seq + ', byId=' + peer.Id);
        }
    }

    for (SeqUpdateDTO u : p.updates) {
        if (existingSeqToId.containsKey(u.sequence)) {
            System.debug(
                '❌ conflict: sequence=' + u.sequence +
                ' already used by peerId=' + existingSeqToId.get(u.sequence)
            );
            throw new AuraHandledException(
                'Sequence ' + u.sequence + ' is already used by another sales rep.'
            );
        }
    }

    System.debug('💡 sequence uniqueness against peers: PASSED');

    /* ================================
       STEP 7: PREPARE UPDATE
       ================================ */
    List<Round_Robin_Pool__c> toUpdate = new List<Round_Robin_Pool__c>();

    for (SeqUpdateDTO u : p.updates) {
        Round_Robin_Pool__c rr = targetMap.get(u.poolId);

        // old value for logging
        Decimal oldSeq = rr.Sequence__c;

        rr.Sequence__c = u.sequence;
        rr.Type__c = finalType;
        rr.Object_Api_Name__c = objectApiName;
        rr.Lead_Source__c = cityWiseOnly ? null : p.leadSource;
        rr.Bucket__c = cityWiseOnly ? null : p.bucket;
        rr.Course_Bucket__c = cityWiseOnly ? null : p.businessVertical;

        toUpdate.add(rr);

        System.debug(
            '💡 prepared update -> Id=' + rr.Id +
            ', oldSeq=' + oldSeq +
            ', newSeq=' + rr.Sequence__c
        );
    }

    System.debug('💡 toUpdate size: ' + toUpdate.size());

    /* ================================
       STEP 8: DML (LWC-SAFE)
       ================================ */
    try {
        if (!toUpdate.isEmpty()) {
            update toUpdate;
            System.debug('✅ update success. records=' + toUpdate.size());
        } else {
            System.debug('ℹ️ nothing to update');
        }
    } catch (Exception e) {
        System.debug('❌ update failed: ' + e.getMessage());
        throw new AuraHandledException('Sequence update failed: ' + e.getMessage());
    }

    System.debug('💡 saveSequences END');
}

   


    @AuraEnabled(cacheable=true)
    public static Map<String, List<String>> getPicklists() {
        Map<String, List<String>> res = new Map<String, List<String>>();

        Schema.DescribeFieldResult city =
            Round_Robin_Pool__c.City__c.getDescribe();
        Schema.DescribeFieldResult course =
            Round_Robin_Pool__c.Course__c.getDescribe();
        Schema.DescribeFieldResult typeF =
            Round_Robin_Pool__c.Type__c.getDescribe();
        Schema.DescribeFieldResult leadSrc =
            Round_Robin_Pool__c.Lead_Source__c.getDescribe();

        res.put('cities', getValues(city));
        res.put('courses', getValues(course));
        res.put('types', getValues(typeF));
        res.put('leadSources', getValues(leadSrc));

        return res;
    }

    private static List<String> getValues(Schema.DescribeFieldResult d) {
        List<String> vals = new List<String>();
        for (Schema.PicklistEntry p : d.getPicklistValues()) {
            if (p.isActive()) vals.add(p.getValue());

        }
        return vals;
    }

    @AuraEnabled(cacheable=true)
    public static List<User> getSalesReps() {
       return [
    SELECT Id, Name
    FROM User
    WHERE IsActive = true
    ORDER BY Name
];

    }
   @AuraEnabled
public static void createRoundRobinEntry(
    String city,
    String leadSource,
    Id salesRepId,
    String course,
    String typeVal,
    Integer weight,
    String objectApiName,
    String businessVertical
) {
    if (String.isBlank(objectApiName)) {
        objectApiName = 'Lead__c';
    }

    String finalType = String.isBlank(typeVal) ? TYPE_CC_PRE : typeVal;
    Boolean cityWiseOnly = isCityWiseOnly(finalType, null);

    if (String.isBlank(city) || salesRepId == null || (!cityWiseOnly && String.isBlank(leadSource))) {
        throw new AuraHandledException('Required fields are missing');
    }

    Round_Robin_Pool__c rr = new Round_Robin_Pool__c();
    rr.City__c = city;
    rr.Lead_Source__c = cityWiseOnly ? null : leadSource;
    rr.Sales_Rep__c = salesRepId;
    rr.Course__c = course != null ? course : 'CMA';
    rr.Type__c = finalType;
    rr.Object_Api_Name__c = resolveObjectApiName(finalType);
    rr.Assigned_Weight__c = weight;
    rr.Active__c = true;
    rr.Course_Bucket__c = businessVertical;  // fixed
  

    insert rr;
}

}
