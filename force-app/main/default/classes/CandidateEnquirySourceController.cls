public without sharing class CandidateEnquirySourceController {

    @AuraEnabled(cacheable=true)
    public static List<SourceCountWrapper> getSourceCounts(
        Id recordId,
        String objectApiName,
        String sourceFieldApiName,
        String candidateFieldApiName
    ) {
        List<SourceCountWrapper> result = new List<SourceCountWrapper>();

        if (String.isBlank(objectApiName) ||
            String.isBlank(sourceFieldApiName) ||
            String.isBlank(candidateFieldApiName) ||
            recordId == null) {
            return result;
        }

    String query =
    'SELECT ' + sourceFieldApiName + ' source, ' +
    'COUNT(Id) total, ' +
    'MAX(LastModifiedDate) lastModified ' +
    'FROM ' + objectApiName + ' ' +
    'WHERE ' + candidateFieldApiName + ' = :recId ' +
    'AND ' + sourceFieldApiName + ' != NULL ' +
    'AND ' + sourceFieldApiName + ' != \'\' ' +
    'GROUP BY ' + sourceFieldApiName + ' ' +
    'ORDER BY MAX(LastModifiedDate) DESC';


Id recId = recordId;
List<AggregateResult> records = Database.query(query);


        for (AggregateResult ar : records) {
            result.add(new SourceCountWrapper(
                (String) ar.get('source'),
                (Integer) ar.get('total'),
                (Datetime) ar.get('lastModified')
            ));
        }

        return result;
    }

    public class SourceCountWrapper {
        @AuraEnabled public String source;
        @AuraEnabled public Integer count;
        @AuraEnabled public Datetime lastModified;

        public SourceCountWrapper(String source, Integer count, Datetime lastModified) {
            this.source = source;
            this.count = count;
            this.lastModified = lastModified;
        }
    }
}