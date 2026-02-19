/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class RoundRobinAssigner {

    public static void assignWithStickyAndRoundRobin(List<SObject> records, String objectApiName, String type) {
        if (records == null || records.isEmpty()) {
            System.debug(LoggingLevel.INFO, 'RoundRobinAssigner.assignWithStickyAndRoundRobin: no records');
            return;
        }

        RoundRobinConfigProvider.Config cfg = RoundRobinConfigProvider.getConfig(objectApiName, type);
        if (cfg == null) {
            System.debug(LoggingLevel.WARN, 'RoundRobinAssigner.assignWithStickyAndRoundRobin: config not found for object=' + objectApiName + ', type=' + type);
            return;
        }
        System.debug(LoggingLevel.INFO, 'RoundRobinAssigner.assignWithStickyAndRoundRobin: start, records=' + records.size() + ', object=' + objectApiName);

        Boolean isMCOM = 'MCOM'.equalsIgnoreCase(type);
        
        if (isMCOM) {
            System.debug(LoggingLevel.INFO, 'RoundRobinAssigner: MCOM detected, skipping sticky assignment, going straight to round robin');
            RoundRobinService.assignForRecords(records, cfg);
            return;
        }
        
        String phoneField  = cfg.phoneField;
        String sourceField = cfg.sourceField;
        String courseField = cfg.courseField;

        Set<String> phones  = new Set<String>();
        Set<String> sources = new Set<String>();
        Set<String> emails  = new Set<String>();

        for (SObject s : records) {
            String phone = (phoneField != null) ? String.valueOf(s.get(phoneField)) : null;
            String src   = (sourceField != null) ? String.valueOf(s.get(sourceField)) : null;
            String email = (objectApiName == 'Lead__c') ? String.valueOf(s.get('Email__c')) : null;

            if (!String.isBlank(phone)) phones.add(phone.trim());
            if (cfg.enableSticky && !String.isBlank(src)) sources.add(src.trim());
            if (!String.isBlank(email)) emails.add(email.trim().toLowerCase());
        }

        Map<String, Id> phoneSourceToUser = new Map<String, Id>();
        Map<String, Id> phoneToLeadOwner = new Map<String, Id>();
        Datetime cutoff = System.now().addSeconds(-30);

        if (cfg.enableSticky && objectApiName != 'Lead__c' && !phones.isEmpty() && (cfg.ignoreSource || !sources.isEmpty())) {
            String soql =
                'SELECT Id,' + cfg.stickyUserField + ',' + phoneField +
                (cfg.ignoreSource ? '' : (',' + sourceField)) +
                ' FROM ' + objectApiName +
                ' WHERE ' + phoneField + ' IN :phones' +
                (cfg.ignoreSource ? '' : (' AND ' + sourceField + ' IN :sources')) +
                ' AND CreatedDate <= :cutoff';

            List<SObject> existing = Database.query(soql);

            for (SObject ex : existing) {
                String phone = (phoneField != null) ? String.valueOf(ex.get(phoneField)) : null;
                String src   = cfg.ignoreSource ? '(ANY)' : String.valueOf(ex.get(sourceField));

                if (String.isBlank(phone)) continue;
                if (!cfg.ignoreSource && String.isBlank(src)) continue;

                String key = phone.trim() + '|' + (cfg.ignoreSource ? '(ANY)' : src.trim());
                if (!phoneSourceToUser.containsKey(key)) {
                    Id userId = (Id) ex.get(cfg.stickyUserField);
                    if (userId != null) phoneSourceToUser.put(key, userId);
                }
            }
        }

        if (objectApiName == 'Lead__c' && !phones.isEmpty()) {
            Set<Id> currentLeadIds = new Set<Id>();
            for (SObject s : records) {
                Id rid = (Id) s.get('Id');
                if (rid != null) currentLeadIds.add(rid);
            }

            String leadSoql = 'SELECT Phone__c, OwnerId FROM Lead__c WHERE Phone__c IN :phones';
            if (!currentLeadIds.isEmpty()) {
                leadSoql += ' AND Id NOT IN :currentLeadIds';
            }
            List<Lead__c> leadList = Database.query(leadSoql);
            for (Lead__c ld : leadList) {
                if (String.isBlank(ld.Phone__c) || ld.OwnerId == null) continue;
                String key = ld.Phone__c.trim();
                if (!phoneToLeadOwner.containsKey(key)) {
                    phoneToLeadOwner.put(key, ld.OwnerId);
                }
            }
        }

        List<SObject> forRoundRobin = new List<SObject>();
        Integer stickyAssigned = 0;

        for (SObject s : records) {
            Boolean assigned = false;

            if (objectApiName == 'Lead__c') {
                String phone = (phoneField != null) ? String.valueOf(s.get(phoneField)) : null;
                if (!String.isBlank(phone)) {
                    String key = phone.trim();
                    Id leadOwner = phoneToLeadOwner.get(key);
                    if (leadOwner != null) {
                        setAssignee(s, cfg.assignToField, leadOwner);
                        assigned = true;
                    }
                }
            }

            if (cfg.enableSticky && objectApiName != 'Lead__c') {
                String phone = (phoneField != null) ? String.valueOf(s.get(phoneField)) : null;
                String src   = cfg.ignoreSource ? '(ANY)' : (sourceField != null ? String.valueOf(s.get(sourceField)) : null);

                if (!String.isBlank(phone) && (cfg.ignoreSource || !String.isBlank(src))) {
                    String key = phone.trim() + '|' + (cfg.ignoreSource ? '(ANY)' : src.trim());
                    Id stickyUser = phoneSourceToUser.get(key);
                    if (stickyUser != null) {
                        setAssignee(s, cfg.assignToField, stickyUser);
                        assigned = true;
                        stickyAssigned++;
                    }
                }
            }

            if (!assigned) forRoundRobin.add(s);
        }

        if (!forRoundRobin.isEmpty()) {
            RoundRobinService.assignForRecords(forRoundRobin, cfg);
        }
        System.debug(LoggingLevel.INFO, 'RoundRobinAssigner.assignWithStickyAndRoundRobin: done, stickyAssigned=' + stickyAssigned + ', roundRobinQueued=' + forRoundRobin.size());
    }

    private static void setAssignee(SObject s, String assignToField, Id userId) {
        if (String.isBlank(assignToField) || userId == null) return;

        if (assignToField == 'OwnerId') {
            s.put('OwnerId', userId);
        } else {
            s.put(assignToField, userId);
        }
    }
}