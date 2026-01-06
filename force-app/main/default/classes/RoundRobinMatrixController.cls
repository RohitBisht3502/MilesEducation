/*
    Author       : ROHIT SINGH BISHT
    Description  :
*/
public without sharing class RoundRobinMatrixController {

    public class FilterInit {
        @AuraEnabled public List<String> cities;
        @AuraEnabled public List<String> leadSources; // holds Bucket values
        @AuraEnabled public List<String> buckets;
          @AuraEnabled public List<String> types;
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
    if (String.isBlank(typeVal) || typeVal == 'Round Robin') {
        return 'Lead__c';
    }
    if (typeVal == 'Eligibility Criteria') {
        return 'Lead';
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
    f.types = typeVals; // ✅ VERY IMPORTANT

    return f;
}

  @AuraEnabled(cacheable=true)
public static MatrixResult getMatrix(
    String city,
    String bucket,
    List<String> leadSources,
    String businessVertical,
    String typeVal,
    Integer pageNumber,
    Integer pageSize
) {
    String finalType = String.isBlank(typeVal)
        ? 'Round Robin'
        : typeVal;

    String objectApiName = resolveObjectApiName(finalType);

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
        if (leadSources != null && !leadSources.isEmpty()) {
            for (String src : leadSources) {
                if (allSources.contains(src)) columns.add(src);
            }
        }
        if (columns.isEmpty()) columns.addAll(allSources);
        columns.sort();

        System.debug(LoggingLevel.DEBUG, 'getMatrix :: columns (final) size=' + columns.size() + ' => ' + columns);

        List<User> reps;
        if (!String.isBlank(city)) {
            reps = [
                SELECT Id, Name, City__c
                FROM User
                WHERE IsActive = true AND City__c = :city
                ORDER BY Name
            ];
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
            typeVal = 'Round Robin';
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


        if (!String.isBlank(bucket)) q += ' AND Bucket__c = :bucket ';
        if (!String.isBlank(businessVertical)) q += ' AND Course_Bucket__c = :businessVertical ';
        if (leadSources != null && !leadSources.isEmpty()) q += ' AND Lead_Source__c IN :leadSources ';

        q += ' ORDER BY Lead_Source__c, Sequence__c ASC, Sales_Rep__r.Name';

        System.debug(LoggingLevel.DEBUG, 'getMatrix :: SOQL => ' + q);

        List<Round_Robin_Pool__c> poolList = Database.query(q);
        System.debug(LoggingLevel.INFO, 'getMatrix :: poolList fetched size=' + (poolList == null ? 0 : poolList.size()));

        Map<Id, Map<String, Round_Robin_Pool__c>> byRep = new Map<Id, Map<String, Round_Robin_Pool__c>>();
        Integer skipped = 0;
        for (Round_Robin_Pool__c p : poolList) {
            if (p.Sales_Rep__c == null || String.isBlank(p.Lead_Source__c)) {
                skipped++;
                continue;
            }
            if (!byRep.containsKey(p.Sales_Rep__c)) byRep.put(p.Sales_Rep__c, new Map<String, Round_Robin_Pool__c>());
            byRep.get(p.Sales_Rep__c).put(p.Lead_Source__c, p);
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

    @AuraEnabled
    public static void saveAssignedWeights(String updatesJson) {
        if (String.isBlank(updatesJson)) return;
        List<WeightUpdate> updates = (List<WeightUpdate>)JSON.deserialize(updatesJson, List<WeightUpdate>.class);
        applyUpdates(updates);
    }



    private static void validateLeadSourceTotals(List<WeightUpdate> updates) {

    if (updates == null || updates.isEmpty()) return;
String city = updates[0].city;
String bucket = updates[0].bucket;
String businessVertical = updates[0].businessVertical;

String typeVal = String.isBlank(updates[0].typeVal)
    ? 'Round Robin'
    : updates[0].typeVal;

// ADD THIS LINE
String objectApiName = resolveObjectApiName(typeVal);


// String objectApiName = resolveObjectApiName(typeVal);



  Integer userCount =
    updates[0].visibleUserCount != null
        ? updates[0].visibleUserCount
        : [
            SELECT COUNT()
            FROM User
            WHERE IsActive = true
            AND City__c = :city
        ];


    // 2️⃣ Collect lead sources & poolIds
    Set<String> sources = new Set<String>();
    Set<Id> poolIds = new Set<Id>();

    for (WeightUpdate w : updates) {
        if (w.leadSource != null) sources.add(w.leadSource);
        if (w.poolId != null) poolIds.add(w.poolId);
    }

    // 3️⃣ DB totals per Lead Source
    Map<String, Decimal> totals = new Map<String, Decimal>();

String aggQuery =
    'SELECT Lead_Source__c src, SUM(Assigned_Weight__c) total ' +
    'FROM Round_Robin_Pool__c ' +
    'WHERE City__c = :city ' +
    'AND Active__c = true ' +
    'AND Lead_Source__c IN :sources ' +
    'AND Object_Api_Name__c = :objectApiName ';


if (!String.isBlank(typeVal)) {
    aggQuery += ' AND Type__c = :typeVal ';
}


if (!String.isBlank(bucket)) {
    aggQuery += ' AND Bucket__c = :bucket ';
}
if (!String.isBlank(businessVertical)) {
    aggQuery += ' AND Course_Bucket__c = :businessVertical ';
}

aggQuery += ' GROUP BY Lead_Source__c';


for (AggregateResult ar : Database.query(aggQuery)) {
    totals.put((String)ar.get('src'), (Decimal)ar.get('total'));
}


    // 4️⃣ Fetch existing records being UPDATED
    Map<Id, Round_Robin_Pool__c> existingMap = new Map<Id, Round_Robin_Pool__c>();
    if (!poolIds.isEmpty()) {
        existingMap = new Map<Id, Round_Robin_Pool__c>([
SELECT Id, Lead_Source__c, Assigned_Weight__c
FROM Round_Robin_Pool__c
WHERE Id IN :poolIds
AND City__c = :city
AND Active__c = true
AND Object_Api_Name__c = :objectApiName
AND Type__c = :updates[0].typeVal


        ]);
    }

    // 5️⃣ Apply updates CORRECTLY
    for (WeightUpdate w : updates) {
        if (w.leadSource == null || w.assignedWeight == null) continue;

        Decimal currentTotal = totals.containsKey(w.leadSource)
            ? totals.get(w.leadSource)
            : 0;

        // 🔁 Existing record → subtract old weight
        if (w.poolId != null && existingMap.containsKey(w.poolId)) {
            Decimal oldWeight = existingMap.get(w.poolId).Assigned_Weight__c;
            if (oldWeight != null) {
                currentTotal -= oldWeight;
            }
        }

        // ➕ Add new weight
        currentTotal += w.assignedWeight;
        totals.put(w.leadSource, currentTotal);
    }

    // 6️⃣ Validate
    for (String src : totals.keySet()) {
        if (totals.get(src) != userCount) {
            throw new AuraHandledException(
                'Total assigned weight for Lead Source "' + src +
                '" must be ' + userCount +
                ', but found ' + totals.get(src)
            );
        }
    }
}


@AuraEnabled
public static void applyUpdates(List<WeightUpdate> updates) {
    if (updates == null || updates.isEmpty()) return;

    validateLeadSourceTotals(updates);

    // Basic safety
    for (WeightUpdate w : updates) {
        if (w.assignedWeight == null || w.assignedWeight < 0) {
            throw new AuraHandledException('Assigned Weight cannot be negative.');
        }
    }

    // Collect keys
    Set<Id> poolIds = new Set<Id>();
    Set<String> leadSources = new Set<String>();
    Set<Id> salesRepIds = new Set<Id>();

    for (WeightUpdate w : updates) {
        if (w.poolId != null) poolIds.add(w.poolId);
        if (w.leadSource != null) leadSources.add(w.leadSource);
        if (w.salesRepId != null) salesRepIds.add(w.salesRepId);
    }

    // Fetch existing pools by Id
    Map<Id, Round_Robin_Pool__c> existingById = new Map<Id, Round_Robin_Pool__c>();
    if (!poolIds.isEmpty()) {
        existingById = new Map<Id, Round_Robin_Pool__c>([
            SELECT Id, City__c, Sales_Rep__c, Lead_Source__c
            FROM Round_Robin_Pool__c
            WHERE Id IN :poolIds
        ]);
    }

    // Fetch existing pools by rep+source (for inserts check)
    Map<String, Round_Robin_Pool__c> existingByKey = new Map<String, Round_Robin_Pool__c>();
    if (!salesRepIds.isEmpty() && !leadSources.isEmpty()) {
        for (Round_Robin_Pool__c rr : [
            SELECT Id, Sales_Rep__c, Lead_Source__c, City__c
            FROM Round_Robin_Pool__c
            WHERE Sales_Rep__c IN :salesRepIds
            AND Lead_Source__c IN :leadSources
        ]) {
            existingByKey.put(rr.Sales_Rep__c + '|' + rr.Lead_Source__c, rr);
        }
    }

    List<Round_Robin_Pool__c> toInsert = new List<Round_Robin_Pool__c>();
    List<Round_Robin_Pool__c> toUpdate = new List<Round_Robin_Pool__c>();

    for (WeightUpdate w : updates) {

        // 🔁 UPDATE
        if (w.poolId != null && existingById.containsKey(w.poolId)) {
            Round_Robin_Pool__c rr = existingById.get(w.poolId);
            rr.Assigned_Weight__c = w.assignedWeight;
            rr.Course__c = w.course;
            rr.Course_Bucket__c = w.businessVertical;
            rr.Bucket__c = w.bucket;
           String typeVal = String.isBlank(w.typeVal) ? 'Round Robin' : w.typeVal;

rr.Type__c = typeVal;
rr.Object_Api_Name__c = resolveObjectApiName(typeVal);

            rr.Active__c = true;
            // ✅ City NOT REQUIRED here
            toUpdate.add(rr);
        }
        // ➕ INSERT
        else {
            if (String.isBlank(w.city)) {
                throw new AuraHandledException('City is required for new entries.');
            }
           String typeVal = String.isBlank(w.typeVal) ? 'Round Robin' : w.typeVal;

toInsert.add(new Round_Robin_Pool__c(
    Sales_Rep__c = w.salesRepId,
    Lead_Source__c = w.leadSource,
    City__c = w.city,
    Assigned_Weight__c = w.assignedWeight,
    Course__c = w.course != null ? w.course : 'CMA',
    Course_Bucket__c = w.businessVertical,
    Bucket__c = w.bucket,
    Type__c = typeVal,
    Active__c = true,
    Object_Api_Name__c = resolveObjectApiName(typeVal)
));

        }
    }

    if (!toUpdate.isEmpty()) update toUpdate;
    if (!toInsert.isEmpty()) insert toInsert;
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
    new Map<Id, Round_Robin_Pool__c>([
        SELECT Id,
               Bucket__c,
               Lead_Source__c,
               City__c,
               Course_Bucket__c
        FROM Round_Robin_Pool__c
        WHERE Id IN :ids
    ]);

for (Round_Robin_Pool__c r : targetMap.values()) {

    if (
        r.Lead_Source__c != p.leadSource ||
        r.City__c != p.city ||
        r.Bucket__c != p.bucket ||
        (
            !String.isBlank(p.businessVertical) &&
            r.Course_Bucket__c != p.businessVertical
        )
    ) {
        throw new AuraHandledException(
            'All sequence updates must belong to the same Lead Source, City, Bucket and Business Vertical.'
        );
    }
}

String finalType = String.isBlank(p.typeVal)
    ? 'Round Robin'
    : p.typeVal;

String objectApiName = resolveObjectApiName(finalType);






    // // City validation is OK
    // if (p.city != null && p.city != r.City__c) {
    //     throw new AuraHandledException('All updates must belong to the selected City.');
    // }



List<Round_Robin_Pool__c> peerList = [
    SELECT Id, Sequence__c, Course_Bucket__c
    FROM Round_Robin_Pool__c
    WHERE Lead_Source__c = :p.leadSource
    AND City__c = :p.city
    AND Bucket__c = :p.bucket
    AND Course_Bucket__c = :p.businessVertical
    AND Type__c = :finalType
    AND Object_Api_Name__c = :resolveObjectApiName(finalType)
    AND Active__c = true
];



// Map current DB sequences for records NOT in update
Map<Integer, Id> existingSeqToId = new Map<Integer, Id>();

for (Round_Robin_Pool__c peer : peerList) {
    if (!ids.contains(peer.Id) && peer.Sequence__c != null) {
        existingSeqToId.put(
            Integer.valueOf(peer.Sequence__c),
            peer.Id
        );
    }
}

// Validate new sequences
for (SeqUpdateDTO u : p.updates) {
    if (existingSeqToId.containsKey(u.sequence)) {
        throw new AuraHandledException(
            'Sequence ' + u.sequence + ' is already used by another sales rep.'
        );
    }
}


        List<Round_Robin_Pool__c> toUpdate = new List<Round_Robin_Pool__c>();
        for (SeqUpdateDTO u : p.updates) {
            toUpdate.add(new Round_Robin_Pool__c(Id = u.poolId, Sequence__c = u.sequence));
        }

        update toUpdate;
         System.debug('Updated Sequences => ' + toUpdate);
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

    if (String.isBlank(city) || String.isBlank(leadSource) || salesRepId == null) {
        throw new AuraHandledException('Required fields are missing');
    }

    Round_Robin_Pool__c rr = new Round_Robin_Pool__c();
    rr.City__c = city;
    rr.Lead_Source__c = leadSource;
    rr.Sales_Rep__c = salesRepId;
    rr.Course__c = course != null ? course : 'CMA';
    rr.Type__c = 'Round Robin';String finalType = String.isBlank(typeVal) ? 'Round Robin' : typeVal;

rr.Type__c = finalType;
rr.Object_Api_Name__c = resolveObjectApiName(finalType);
  rr.Assigned_Weight__c = weight;
    rr.Active__c = true;
    rr.Course_Bucket__c = businessVertical;  // fixed
  

    insert rr;
}

}