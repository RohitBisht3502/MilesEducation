global class LeadCityUpdateBatch implements Database.Batchable<SObject>, Database.Stateful {

    global Set<Id> leadIds;

    global LeadCityUpdateBatch(Set<Id> leadIds) {
        this.leadIds = leadIds;
    }

    // -----------------------------
    // 1️⃣ Start method: fetch Leads by Id
    // -----------------------------
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, FirstName, LastName, Email, Phone, Coming_From__c, City__c
            FROM Lead
            WHERE Id IN :leadIds
        ]);
    }

    // -----------------------------
    // 2️⃣ Execute method: call API and update City
    // -----------------------------
    global void execute(Database.BatchableContext bc, List<Lead> leadList) {
        if (leadList == null || leadList.isEmpty()) return;

        List<Lead> leadsToUpdate = new List<Lead>();
        List<Integration_Log__c> logs = new List<Integration_Log__c>();

        for (Lead ld : leadList) {
            // Fetch city from API with logging
            String city = LeadCityClassifier.fetchCityForLeadWithLogging(ld, logs);

            // Update only if city is different
            if (!String.isBlank(city) && ld.City__c != city) {
                ld.City__c = city;
                leadsToUpdate.add(ld);
            }
        }

        // Update all Leads in bulk
        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }

        // Insert all collected logs
        if (!logs.isEmpty()) {
            IntegrationLogUtil.insertLogs(logs);
        }
    }

    // -----------------------------
    // 3️⃣ Finish method
    // -----------------------------
    global void finish(Database.BatchableContext bc) {
        System.debug('✅ LeadCityUpdateBatch finished for Lead IDs: ' + leadIds);
    }
}