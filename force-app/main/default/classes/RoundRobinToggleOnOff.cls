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
        // city -> ON/OFF from City CMDT (On__c checkbox)
        Map<String, String> cityStatusFromMdt = new Map<String, String>();
        try {
            List<SObject> cityMdtRows = Database.query(
                'SELECT DeveloperName, MasterLabel, Label, On__c FROM City__mdt'
            );
            for (SObject row : cityMdtRows) {
                String cityName = (String) row.get('Label');
                if (String.isBlank(cityName)) cityName = (String) row.get('MasterLabel');
                if (String.isBlank(cityName)) cityName = (String) row.get('DeveloperName');
                if (String.isBlank(cityName)) continue;

                Boolean isOn = (Boolean) row.get('On__c');
                cityStatusFromMdt.put(
                    cityName,
                    (isOn == true) ? 'ON' : 'OFF'
                );
            }
        } catch (Exception ex) {
            System.debug('City__mdt read failed, defaulting status to ON. ' + ex.getMessage());
        }

        List<CityStatusWrapper> res = new List<CityStatusWrapper>();
        for (String city : cityStatusFromMdt.keySet()) {
            String status = cityStatusFromMdt.containsKey(city) ? cityStatusFromMdt.get(city) : 'ON';
            res.add(new CityStatusWrapper(city, status, 0));
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

    Map<String, Boolean> cityToIsOn = new Map<String, Boolean>();
    for (CityStatusWrapper w : updates) {
        System.debug('wrapper >>> city=' + w.city + ', status=' + w.status + ', cnt=' + w.salesRepCount);
        if (w == null || String.isBlank(w.city) || String.isBlank(w.status)) continue;
        cityToIsOn.put(w.city.trim().toUpperCase(), w.status.trim().toUpperCase() == 'ON');
    }

    if (cityToIsOn.isEmpty()) return;

    List<City__mdt> cityMdtRecs = [
        SELECT DeveloperName, MasterLabel, Label, ON__c
        FROM City__mdt
    ];

    Metadata.DeployContainer container = new Metadata.DeployContainer();
    Integer changed = 0;

    for (City__mdt rec : cityMdtRecs) {
        String cityByName = String.isNotBlank(rec.Label) ? rec.Label.trim().toUpperCase() : null;
        String cityByLabel = String.isNotBlank(rec.MasterLabel) ? rec.MasterLabel.trim().toUpperCase() : null;
        Boolean newIsOn = cityByName != null ? cityToIsOn.get(cityByName) : null;
        if (newIsOn == null && cityByLabel != null) {
            newIsOn = cityToIsOn.get(cityByLabel);
        }
        if (newIsOn == null && String.isNotBlank(rec.DeveloperName)) {
            newIsOn = cityToIsOn.get(rec.DeveloperName.trim().toUpperCase());
        }
        if (newIsOn == null) {
            continue;
        }

        Metadata.CustomMetadata cmd = new Metadata.CustomMetadata();
        cmd.fullName = 'City__mdt.' + rec.DeveloperName;
        cmd.label = rec.MasterLabel;
        cmd.values = new List<Metadata.CustomMetadataValue>();

        Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
        v.field = 'ON__c';
        v.value = newIsOn;
        cmd.values.add(v);

        container.addMetadata(cmd);
        changed++;
    }

    if (changed > 0) {
        Metadata.Operations.enqueueDeployment(container, new CityMasterDeployCallback());
    }
    }

    public class CityMasterDeployCallback implements Metadata.DeployCallback {
        public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
            System.debug('City master metadata deployment status: ' + result.status);
        }
    }

}
