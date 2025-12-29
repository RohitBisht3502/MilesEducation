/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class CandidateTriggerHelperClass {

    public static void handleBeforeInsert(List<Lead> newLeads) {
        // RoundRobinService.assignForLeads(newLeads);
        BucketAssignmentService.assignBucket((List<SObject>)newLeads, null);
    }
    
    public static void handleBeforeUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        // TriggerRoundRobinService.handleBeforeUpdate(newLeads, oldMap);
        BucketAssignmentService.assignBucket((List<SObject>)newLeads,(Map<Id, SObject>)oldMap);
    }

    public static void handleAfterInsert(List<Lead> newLeads) {
        if (newLeads == null || newLeads.isEmpty()) return;
        System.debug('Inside handleAfterInsert line 13 ');
        Set<Id> newLeadIds = new Set<Id>();
        for (Lead ld : newLeads) {
            if (ld.Id != null) newLeadIds.add(ld.Id);
        }
        if (!newLeadIds.isEmpty()) {
          //  LeadCityClassifier.enqueueLeadCityUpdate(newLeadIds);
        }

        Set<Id> leadsForZoom = new Set<Id>();
        for (Lead ld : newLeads) {
            System.debug('Inside ld line 13 '+ld);
            Boolean emailOk   = String.isNotBlank(ld.Email);
            Boolean wantsWeb  = (ld.Register_For_Webinar__c == true);
            Boolean noWebinar = String.isNotBlank(ld.Interested_Webinar_Id__c);
            System.debug('>>>> '+emailOk);
            System.debug('>>>> '+wantsWeb);
            System.debug('>>>> '+noWebinar);
           if (emailOk && wantsWeb && noWebinar) {
                leadsForZoom.add(ld.Id);
            }
        }
        if (!leadsForZoom.isEmpty()) {
            System.debug('Inside handleAfterInsert queue ');
            System.enqueueJob(new LeadZoomRegistrationJob(leadsForZoom));
        }
    }

    // public static void handleAfterUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
    //     if (newLeads == null || newLeads.isEmpty() || oldMap == null) return;

    //     Set<Id> leadsForZoom = new Set<Id>();

    //     for (Lead ld : newLeads) {
    //         Lead oldLd = oldMap.get(ld.Id);

    //         Boolean nowChecked = (ld.Register_Zoom_Integration__c == true);
    //         Boolean wasChecked = (oldLd != null && oldLd.Register_Zoom_Integration__c == true);

    //       //  if (nowChecked && !wasChecked && String.isNotBlank(ld.Phone) && String.isNotBlank(ld.FirstName)) {
    //             leadsForZoom.add(ld.Id);
    //        // }
    //     }

    //     if (!leadsForZoom.isEmpty()) {
    //         System.enqueueJob(new LeadZoomRegistrationJob(leadsForZoom));
    //     }
    // }
	
        // Method to handle after insert
    public static void handleCandidateIdAfterInsert(List<Lead> newLeads) {
        List<Lead> leadsToUpdate = new List<Lead>();
        Map<String, String> cityCodeMap = getCityCodeMap();
        
        // Query the leads again to get the auto-number values
        Map<Id, Lead> leadMap = new Map<Id, Lead>([
            SELECT Id, City__c, Candidate_Id__c, Candidate_Running_Number__c 
            FROM Lead 
            WHERE Id IN :newLeads 
            AND City__c != NULL
        ]);
        
        for (Lead lead : leadMap.values()) {
            // Only process if City is not blank and Candidate Id is not already set
            if (String.isNotBlank(lead.City__c) && String.isBlank(lead.Candidate_Id__c)) {
                String cityName = lead.City__c.trim();
                String cityCode = cityCodeMap.get(cityName.toLowerCase());
                String runningNumber = extractRunningNumber(lead.Candidate_Running_Number__c);
                
                Lead updatedLead = new Lead(Id = lead.Id);
                if (String.isNotBlank(cityCode)) {
                    updatedLead.Candidate_Id__c = cityCode + '-' + runningNumber;
                } 
                leadsToUpdate.add(updatedLead);
                System.debug('Candidate Id After Insert :::::'+updatedLead.Candidate_ID__c);
            }
        }
        
        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
    }
    
    // Method to handle before update
    public static void handleCandidateIdBeforeUpdate(List<Lead> newLeads, Map<Id, Lead> oldLeadsMap) {
        List<Lead> leadsToProcess = new List<Lead>();
        
        for (Lead newLead : newLeads) {
            Lead oldLead = oldLeadsMap.get(newLead.Id);
            
            // Check conditions for update
            Boolean wasCityBlank = String.isBlank(oldLead.City__c);
            Boolean isCityNowNotBlank = String.isNotBlank(newLead.City__c);
            Boolean isCandidateIdBlank = String.isBlank(newLead.Candidate_Id__c);
            
            // Process only when:
            // - Old City was blank AND New City is not blank (user added City)
            // - AND Candidate Id is blank (not previously generated)
            if (wasCityBlank && isCityNowNotBlank && isCandidateIdBlank) {
                leadsToProcess.add(newLead);
            }
        }
        
        if (!leadsToProcess.isEmpty()) {
            generateCandidateIds(leadsToProcess);
        }
    }
    
    // Method to generate Candidate IDs (for before update only)
    private static void generateCandidateIds(List<Lead> leads) {
        // Get all city mappings from custom metadata
        Map<String, String> cityCodeMap = getCityCodeMap();
        
        for (Lead lead : leads) {
            if (String.isNotBlank(lead.City__c) && String.isBlank(lead.Candidate_Id__c)) {
                String cityName = lead.City__c.trim();
                String cityCode = cityCodeMap.get(cityName.toLowerCase());
                String runningNumber = extractRunningNumber(lead.Candidate_Running_Number__c);
                
                System.debug('Candidate Running Number is :::::'+runningNumber);

                
                if (String.isNotBlank(cityCode)) {
                    lead.Candidate_Id__c = cityCode + '-' + runningNumber;
                } 
                System.debug('Candidate Id Is :::::'+lead.Candidate_ID__c);
            }
        }
    }
    
    // Method to extract running number from auto-number field
    private static String extractRunningNumber(String candidateRunningNumber) {
        if (String.isBlank(candidateRunningNumber)) {
            return '100000'; // Default if auto-number not generated yet
        }
        
        // Extract numbers from auto-number format "CRN-{000000}"
        if (candidateRunningNumber.contains('CRN-')) {
            return candidateRunningNumber.substringAfter('CRN-');
        }
        
        return candidateRunningNumber;
    }
    
    // Method to get city code mapping from custom metadata
    private static Map<String, String> getCityCodeMap() {
        Map<String, String> cityCodeMap = new Map<String, String>();
        
        try {
            List<City_Master__mdt> cities = [
                SELECT MasterLabel, City_Name__c, City_Code__c 
                FROM City_Master__mdt 
                WHERE City_Name__c != NULL 
                AND City_Code__c != NULL
            ];
            
            for (City_Master__mdt city : cities) {
                // Use both MasterLabel and City_Name__c for flexibility
                String cityName = String.isNotBlank(city.City_Name__c) ? 
                                 city.City_Name__c : city.MasterLabel;
                cityCodeMap.put(cityName.toLowerCase(), city.City_Code__c);
            }
        } catch (Exception e) {
            System.debug('Error fetching city metadata: ' + e.getMessage());
        }
        System.debug('City Code for Selected City from Candidate is :::::'+cityCodeMap);
        return cityCodeMap;
    }
    
    
    public static void transferRecordsOnConversion(List<Lead> newLeads, Map<Id, Lead> oldLeadsMap) {
        
        // Step 1: Find which leads were just converted
        Map<Id, Id> convertedLeadToAccount = new Map<Id, Id>();
        
        for (Lead newLead : newLeads) {
            Lead oldLead = oldLeadsMap.get(newLead.Id);
            
            // Check if this lead was just converted
            if (newLead.isConverted && (oldLead == null || !oldLead.isConverted)) {
                if (newLead.ConvertedAccountId != null) {
                    convertedLeadToAccount.put(newLead.Id, newLead.ConvertedAccountId);
                }
            }
        }
        
        // If no leads were converted, do nothing
        if (convertedLeadToAccount.isEmpty()) {
            return;
        }
        
        // Step 2: Get all related records
        Set<Id> convertedLeadIds = convertedLeadToAccount.keySet();
        
        // Get emails related to converted leads
        List<Email__c> emails = [SELECT Id, Candidate__c FROM Email__c 
                                WHERE Candidate__c IN :convertedLeadIds];
        
        // Get custom leads related to converted leads
        List<Lead__c> customLeads = [SELECT Id, Candidate__c FROM Lead__c 
                                    WHERE Candidate__c IN :convertedLeadIds];
        
        // Get phone numbers related to converted leads
        List<Phone_Number__c> phoneNumbers = [SELECT Id, Candidate__c FROM Phone_Number__c 
                                            WHERE Candidate__c IN :convertedLeadIds];
        
        // Step 3: Update records with Account Id
        List<SObject> recordsToUpdate = new List<SObject>();
        
        // Update emails
        for (Email__c email : emails) {
            email.Student__c = convertedLeadToAccount.get(email.Candidate__c);
            recordsToUpdate.add(email);
        }
        
        // Update custom leads
        for (Lead__c customLead : customLeads) {
            customLead.Student__c = convertedLeadToAccount.get(customLead.Candidate__c);
            recordsToUpdate.add(customLead);
        }
        
        // Update phone numbers
        for (Phone_Number__c phone : phoneNumbers) {
            phone.Student__c = convertedLeadToAccount.get(phone.Candidate__c);
            recordsToUpdate.add(phone);
        }
        
        // Step 4: Save all changes
        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
    }

}