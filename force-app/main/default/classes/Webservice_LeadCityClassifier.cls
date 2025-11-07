public class Webservice_LeadCityClassifier {

    @future(callout = true)
    public static void callCityClassifierAsync(Set<Id> leadIds) {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();

        if (leadIds == null || leadIds.isEmpty()) {
            logs.add(IntegrationLogUtil.buildLog('Lead City Classifier', null, null, 'No leadIds provided', 'Skipped', null));
            IntegrationLogUtil.insertLogs(logs); return;
        }

        External_Service_Config__mdt cfg;
        try {
            cfg = [SELECT Endpoint_URL__c, Http_Method__c, Api_Key__c, Api_Key_Header__c, Is_Active__c  FROM External_Service_Config__mdt WHERE DeveloperName = 'Lead_City_Classifier' LIMIT 1];
        } catch (Exception e) {
            logs.add(IntegrationLogUtil.buildLog('Lead City Classifier', null, null, 'Config load error: ' + e.getMessage(), 'Failed', null));
            IntegrationLogUtil.insertLogs(logs); return;
        }

        if (cfg == null || !cfg.Is_Active__c || String.isBlank(cfg.Endpoint_URL__c) || String.isBlank(cfg.Http_Method__c)) {
            logs.add(IntegrationLogUtil.buildLog('Lead City Classifier', null, null, 'Invalid/inactive config', 'Failed', null));
            IntegrationLogUtil.insertLogs(logs); return;
        }

        List<Lead> leads = [SELECT Id, FirstName, LastName, Email, Phone, Coming_From__c, City__c FROM Lead WHERE Id IN :leadIds];
        if (leads.isEmpty()) {
            logs.add(IntegrationLogUtil.buildLog('Lead City Classifier', null, null, 'No leads found for provided ids', 'Skipped', null));
            IntegrationLogUtil.insertLogs(logs); return;
        }

        Http http = new Http();
        Integer ok = 0, err = 0;

        for (Lead ld : leads) {
            String reqPayload = null, resPayload = null, city = null;
            Integer statusCode = null;

            try {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(cfg.Endpoint_URL__c);
                req.setMethod(cfg.Http_Method__c);
                req.setHeader('Content-Type', 'application/json');
                if (!String.isBlank(cfg.Api_Key__c) && !String.isBlank(cfg.Api_Key_Header__c)) req.setHeader(cfg.Api_Key_Header__c, cfg.Api_Key__c);

                reqPayload = LeadCityClassifierDTO.toJsonFromLead(ld);
                req.setBody(reqPayload);
                HttpResponse res = http.send(req);
                statusCode = res.getStatusCode();
                resPayload = res.getBody();

                if (statusCode == 200 && String.isNotBlank(resPayload)) {
                    Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(resPayload);
                    if (result != null) {
                        if (result.containsKey('nearest_city')) city = String.valueOf(result.get('nearest_city'));
                        else if (result.containsKey('city')) city = String.valueOf(result.get('city'));
                        else if (result.containsKey('predicted_city')) city = String.valueOf(result.get('predicted_city'));
                        else if (result.containsKey('result')) {
                            Map<String, Object> innerMap = (Map<String, Object>) result.get('result');
                            if (innerMap != null) {
                                if (innerMap.containsKey('city')) city = String.valueOf(innerMap.get('city'));
                                else if (innerMap.containsKey('nearest_city')) city = String.valueOf(innerMap.get('nearest_city'));
                            }
                        }
                    }
                }

                if (String.isNotBlank(city)) {
                    ld.City__c = city; ok++;
                    logs.add(IntegrationLogUtil.buildLog('Lead City', reqPayload, resPayload, null, 'Success', statusCode));
                } else {
                    err++;
                    logs.add(IntegrationLogUtil.buildLog('Lead City', reqPayload, resPayload, (statusCode == 200 ? 'No city found in response' : 'HTTP ' + statusCode), 'Failed', statusCode));
                }
            } catch (Exception ex) {
                err++;
                logs.add(IntegrationLogUtil.buildLog('Lead City', reqPayload, resPayload, 'Exception: ' + ex.getMessage(), 'Failed', statusCode));
            }
        }

        try {
            if (!leads.isEmpty()) update leads;
        } catch (DmlException d) {
            err++; logs.add(IntegrationLogUtil.buildLog('Lead City Classifier', null, null, 'DML error: ' + d.getMessage(), 'Failed', null));
        }

        logs.add(IntegrationLogUtil.buildLog('Lead City Classifier', '(summary)', null, null, (err > 0 ? 'Warning' : 'Success') + ' — Success=' + ok + ', Errors=' + err, null));
        if (!logs.isEmpty()) IntegrationLogUtil.insertLogs(logs);
    }
}