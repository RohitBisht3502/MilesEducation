public without sharing class LeadCityClassifier {

    private static final String API_ENDPOINT = 'https://gvqz37ay7d.execute-api.ap-south-1.amazonaws.com/miles360/city_classifier';
    private static final String API_KEY = 'gAkgs8n3PQ8QnanrfsueA5KpXNOlpwJw6WtjD2hR';

    // Fetch city for a given custom Lead__c and log the process
    public static String fetchCityForLeadWithLogging(Lead__c ld, List<Integration_Log__c> logs) {
        Http http = new Http();
        String requestPayload = '';
        String responsePayload = '';
        String city = null;

        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint(API_ENDPOINT);
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setHeader('x-api-key', API_KEY);

            // Prepare request payload
           // String fullName = ((ld.First_Name__c != null ? ld.First_Name__c : '') + ' ' + (ld.Last_Name__c != null ? ld.Last_Name__c : '')).trim();
            Map<String, Object> payload = new Map<String, Object>{
                'email' => ld.Email__c,
                'phone' => ld.Phone__c
            //   'phone' => '9560682867'
            };

            requestPayload = JSON.serialize(payload);
            request.setBody(requestPayload);

            // Call API
            HttpResponse response = http.send(request);
            responsePayload = response.getBody();

            if (response.getStatusCode() == 200 && String.isNotBlank(responsePayload)) {
                Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(responsePayload);
                city = extractCityFromResponse(result);
            }

            // Log response
            logs.add(IntegrationLogUtil.buildLog(
                'Lead__c City',
                requestPayload,
                responsePayload,
                String.isBlank(city) ? 'No city found in API response' : null,
                String.isNotBlank(city) ? 'Success' : 'Failed',
                response.getStatusCode()
            ));

        } catch (Exception ex) {
            logs.add(IntegrationLogUtil.buildLog(
                'Lead__c City',
                requestPayload,
                responsePayload,
                'Exception: ' + ex.getMessage(),
                'Failed',
                null
            ));
        }

      // return city;
        return 'Delhi';
    }

    // Helper to extract city from nested response structures
    private static String extractCityFromResponse(Map<String, Object> result) {
        if (result == null) return null;

        if (result.containsKey('city')) return (String) result.get('city');
        if (result.containsKey('nearest_city')) return (String) result.get('nearest_city');
        if (result.containsKey('predicted_city')) return (String) result.get('predicted_city');

        if (result.containsKey('result')) {
            Map<String, Object> nestedResult = (Map<String, Object>) result.get('result');
            if (nestedResult != null) {
                if (nestedResult.containsKey('city')) return (String) nestedResult.get('city');
                if (nestedResult.containsKey('nearest_city')) return (String) nestedResult.get('nearest_city');
            }
        }
        return null;
    }

    // Queueable job for async city update
    public class UpdateLeadCityJob implements Queueable, Database.AllowsCallouts {
        private Set<Id> leadIds;

        public UpdateLeadCityJob(Set<Id> leadIds) {
            this.leadIds = leadIds;
        }

        public void execute(QueueableContext ctx) {
            if (leadIds == null || leadIds.isEmpty()) return;

            List<Lead__c> leads = [
                SELECT Id, Email__c, Phone__c,  City__c  FROM Lead__c  WHERE Id IN :leadIds];

            List<Integration_Log__c> logs = new List<Integration_Log__c>();
            List<Lead__c> leadsToUpdate = new List<Lead__c>();

            for (Lead__c ld : leads) {
                String city = fetchCityForLeadWithLogging(ld, logs);
                if (!String.isBlank(city) && ld.City__c != city) {
                    ld.City__c = city;
                    leadsToUpdate.add(ld);
                }
            }

            if (!leadsToUpdate.isEmpty()) update leadsToUpdate;
            if (!logs.isEmpty()) IntegrationLogUtil.insertLogs(logs);
        }
    }

    // Public method to enqueue the update job
    public static void enqueueLeadCityUpdate(Set<Id> leadIds) {
        if (leadIds != null && !leadIds.isEmpty()) {
            System.enqueueJob(new UpdateLeadCityJob(leadIds));
        }
    }
}