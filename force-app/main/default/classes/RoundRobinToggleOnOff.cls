public with sharing class RoundRobinToggleOnOff {

  public class CityStatusWrapper {
    @AuraEnabled public String city;
    @AuraEnabled public String status;
    @AuraEnabled public Integer salesRepCount;

    public CityStatusWrapper() {}

    public CityStatusWrapper(String city, String status, Integer cnt) {
      this.city = city;
      this.status = status;
      this.salesRepCount = cnt;
    }
  }

    @AuraEnabled(cacheable=true)
    public static List<CityStatusWrapper> getCityStatuses() {
        // city -> distinct sales reps
        Map<String, Set<Id>> cityToReps = new Map<String, Set<Id>>();
        // city -> has any inactive record
        Set<String> cityHasInactive = new Set<String>();

        for (Round_Robin_Pool__c r : [
            SELECT City__c, Active__c, Sales_Rep__c
            FROM Round_Robin_Pool__c
            WHERE City__c != null
        ]) {
            String city = r.City__c;

            if (!cityToReps.containsKey(city)) {
                cityToReps.put(city, new Set<Id>());
            }

            if (r.Sales_Rep__c != null) {
                cityToReps.get(city).add(r.Sales_Rep__c); 
            }

            if (r.Active__c == false) {
                cityHasInactive.add(city);
            }
        }

        List<CityStatusWrapper> res = new List<CityStatusWrapper>();
        for (String city : cityToReps.keySet()) {
            Integer repCount = cityToReps.get(city).size();
            String status = cityHasInactive.contains(city) ? 'OFF' : 'ON';
            res.add(new CityStatusWrapper(city, status, repCount));
        }
        return res;
    }

    @AuraEnabled
    public static void updateCityStatuses(String updatesJson) {
    System.debug('updatesJson >>> ' + updatesJson);

    if (String.isBlank(updatesJson)) return;

    List<CityStatusWrapper> updates;
    try {
        updates = (List<CityStatusWrapper>) JSON.deserialize(updatesJson, List<CityStatusWrapper>.class);
    } catch (Exception ex) {
        System.debug('Deserialize error >>> ' + ex.getMessage());
        throw new AuraHandledException('Invalid payload received from UI.');
    }

    System.debug('updates >>> ' + JSON.serialize(updates));
    if (updates == null || updates.isEmpty()) return;

    Map<String, Boolean> cityToActive = new Map<String, Boolean>();
    for (CityStatusWrapper w : updates) {
        System.debug('wrapper >>> city=' + w.city + ', status=' + w.status + ', cnt=' + w.salesRepCount);
        if (w == null || String.isBlank(w.city) || String.isBlank(w.status)) continue;
        cityToActive.put(w.city.trim(), w.status.trim().toUpperCase() == 'ON');
    }

    if (cityToActive.isEmpty()) return;

    Set<String> citiesToUpdate = new Set<String>();
    for (String c : cityToActive.keySet()) {
        if (!String.isBlank(c)) citiesToUpdate.add(c);
    }
    if (citiesToUpdate.isEmpty()) return;

    List<Round_Robin_Pool__c> recs = [
        SELECT Id, City__c, Active__c
        FROM Round_Robin_Pool__c
        WHERE City__c IN :citiesToUpdate
    ];

    List<Round_Robin_Pool__c> recsToUpdate = new List<Round_Robin_Pool__c>();
    for (Round_Robin_Pool__c r : recs) {
        Boolean newActive = cityToActive.get(r.City__c);
        if (newActive != null && r.Active__c != newActive) {
        r.Active__c = newActive;
        recsToUpdate.add(r);
        }
    }

    if (!recsToUpdate.isEmpty()) {
        try {
        update recsToUpdate;
        } catch (DmlException e) {
        System.debug('DML Error updating Round Robin Pools: ' + e.getMessage());
        throw new AuraHandledException('Unable to update Round Robin Pools. Please check triggers and validation rules.');
        }
    }
    }

}