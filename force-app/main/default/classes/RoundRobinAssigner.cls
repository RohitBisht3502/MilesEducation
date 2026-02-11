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
        System.debug(LoggingLevel.INFO, 'RoundRobinAssigner.assignWithStickyAndRoundRobin: start, records=' + records.size() + ', object=' + objectApiName + ', type=' + type);
        System.debug(LoggingLevel.INFO, 'RoundRobinAssigner config: enableSticky=' + cfg.enableSticky + ', ignoreSource=' + cfg.ignoreSource + ', assignTo=' + cfg.assignToField + ', phoneField=' + cfg.phoneField + ', sourceField=' + cfg.sourceField + ', courseField=' + cfg.courseField);

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
        Datetime cutoff = System.now().addSeconds(-30);
        Boolean skipLeadOwnerCheck = (type != null && (type.equalsIgnoreCase('GP') || type.equalsIgnoreCase('MCOM')));
        System.debug(LoggingLevel.INFO, 'RoundRobinAssigner: sticky cutoff=' + cutoff);

        if (cfg.enableSticky && !phones.isEmpty() && (cfg.ignoreSource || !sources.isEmpty())) {
            String soql =
                'SELECT Id,' + cfg.stickyUserField + ',' + phoneField +
                (cfg.ignoreSource ? '' : (',' + sourceField)) +
                ' FROM ' + objectApiName +
                ' WHERE ' + phoneField + ' IN :phones' +
                (cfg.ignoreSource ? '' : (' AND ' + sourceField + ' IN :sources')) +
                ' AND CreatedDate <= :cutoff';

            System.debug(LoggingLevel.INFO, 'RoundRobinAssigner sticky SOQL=' + soql);
            List<SObject> existing = Database.query(soql);
            System.debug(LoggingLevel.INFO, 'RoundRobinAssigner sticky matches=' + existing.size());

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

        Map<String, Id> phoneToStudentOwner = new Map<String, Id>();
        Map<String, Id> phoneToLeadOwner = new Map<String, Id>();
        Map<String, Id> emailToStudentOwner = new Map<String, Id>();
        Map<String, Id> emailToLeadOwner = new Map<String, Id>();

        if (objectApiName == 'Lead__c' && !skipLeadOwnerCheck && (!phones.isEmpty() || !emails.isEmpty())) {
            Set<Id> currentLeadIds = new Set<Id>();
            for (SObject s : records) {
                Id rid = (Id) s.get('Id');
                if (rid != null) currentLeadIds.add(rid);
            }

            List<String> whereParts = new List<String>();
            if (!phones.isEmpty()) {
                whereParts.add(phoneField + ' IN :phones');
            }
            if (!emails.isEmpty()) {
                whereParts.add('Email__c IN :emails');
            }

            String leadSoql =
                'SELECT Id, OwnerId, ' + phoneField + ', Email__c, Payment_Received__c, Student__r.OwnerId ' +
                'FROM Lead__c ' +
                'WHERE (' + String.join(whereParts, ' OR ') + ')';
            if (!currentLeadIds.isEmpty()) {
                leadSoql += ' AND Id NOT IN :currentLeadIds';
            }

            List<Lead__c> existingLeads = Database.query(leadSoql);
            for (Lead__c exLead : existingLeads) {
                String phone = (phoneField != null) ? String.valueOf(exLead.get(phoneField)) : null;
                String email = exLead.Email__c;

                if (exLead.Payment_Received__c == 'Fully Received' && exLead.Student__r != null && exLead.Student__r.OwnerId != null) {
                    if (!String.isBlank(phone) && !phoneToStudentOwner.containsKey(phone.trim())) {
                        phoneToStudentOwner.put(phone.trim(), exLead.Student__r.OwnerId);
                    }
                    if (!String.isBlank(email)) {
                        String eKey = email.trim().toLowerCase();
                        if (!emailToStudentOwner.containsKey(eKey)) {
                            emailToStudentOwner.put(eKey, exLead.Student__r.OwnerId);
                        }
                    }
                } else if (exLead.OwnerId != null) {
                    if (!String.isBlank(phone) && !phoneToLeadOwner.containsKey(phone.trim())) {
                        phoneToLeadOwner.put(phone.trim(), exLead.OwnerId);
                    }
                    if (!String.isBlank(email)) {
                        String eKey = email.trim().toLowerCase();
                        if (!emailToLeadOwner.containsKey(eKey)) {
                            emailToLeadOwner.put(eKey, exLead.OwnerId);
                        }
                    }
                }
            }
            System.debug(LoggingLevel.INFO, 'RoundRobinAssigner existing lead owners: studentPhone=' + phoneToStudentOwner.size() + ', leadPhone=' + phoneToLeadOwner.size() + ', studentEmail=' + emailToStudentOwner.size() + ', leadEmail=' + emailToLeadOwner.size());
        }

        List<SObject> forRoundRobin = new List<SObject>();
        Integer stickyAssigned = 0;
        Integer preAssigned = 0;

        for (SObject s : records) {
            Boolean assigned = false;

            if (objectApiName == 'Lead__c' && !skipLeadOwnerCheck) {
                String phone = (phoneField != null) ? String.valueOf(s.get(phoneField)) : null;
                String email = String.valueOf(s.get('Email__c'));

                if (!String.isBlank(phone)) {
                    String key = phone.trim();
                    Id studentOwner = phoneToStudentOwner.get(key);
                    if (studentOwner != null) {
                        setAssignee(s, cfg.assignToField, studentOwner);
                        assigned = true;
                        preAssigned++;
                    } else {
                        Id leadOwner = phoneToLeadOwner.get(key);
                        if (leadOwner != null) {
                            setAssignee(s, cfg.assignToField, leadOwner);
                            assigned = true;
                            preAssigned++;
                        }
                    }
                }

                if (!assigned && !String.isBlank(email)) {
                    String eKey = email.trim().toLowerCase();
                    Id studentOwner = emailToStudentOwner.get(eKey);
                    if (studentOwner != null) {
                        setAssignee(s, cfg.assignToField, studentOwner);
                        assigned = true;
                        preAssigned++;
                    } else {
                        Id leadOwner = emailToLeadOwner.get(eKey);
                        if (leadOwner != null) {
                            setAssignee(s, cfg.assignToField, leadOwner);
                            assigned = true;
                            preAssigned++;
                        }
                    }
                }
            }

            if (cfg.enableSticky) {
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
        System.debug(LoggingLevel.INFO, 'RoundRobinAssigner.assignWithStickyAndRoundRobin: done, preAssigned=' + preAssigned + ', stickyAssigned=' + stickyAssigned + ', roundRobinQueued=' + forRoundRobin.size());
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
