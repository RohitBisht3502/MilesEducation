public without sharing class CallDispositionConfigService {
    public class CallDispositionDTO {
        @AuraEnabled public String l1;
        @AuraEnabled public String l2;
        @AuraEnabled public String tagLevel;
        @AuraEnabled public Boolean commentNeeded;
    }

    @AuraEnabled(cacheable=true)
    public static List<CallDispositionDTO> getDispositions() {
        List<Call_Disposition__mdt> rows = [
            SELECT L1__c, L2__c, Tag_Level__c, Commented_Needed__c
            FROM Call_Disposition__mdt
            ORDER BY L1__c, L2__c, Tag_Level__c
        ];

        List<CallDispositionDTO> result = new List<CallDispositionDTO>();
        for (Call_Disposition__mdt row : rows) {
            CallDispositionDTO dto = new CallDispositionDTO();
            dto.l1 = row.L1__c;
            dto.l2 = row.L2__c;
            dto.tagLevel = row.Tag_Level__c;
            dto.commentNeeded = row.Commented_Needed__c;
            result.add(dto);
        }
        return result;
    }
}