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
        Map<String, Id> phoneToStudentOwner = new Map<String, Id>();
        Map<String, Id> phoneToCandidateOwner = new Map<String, Id>();
        Map<String, Id> emailToStudentOwner = new Map<String, Id>();
        Map<String, Id> emailToCandidateOwner = new Map<String, Id>();
        Map<String, Id> emailToLeadOwner = new Map<String, Id>();
        Datetime cutoff = System.now().addSeconds(-30);

        if (cfg.enableSticky && !phones.isEmpty() && (cfg.ignoreSource || !sources.isEmpty())) {
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
            String leadSoql =
                'SELECT Id, OwnerId, Student__c, Student__r.OwnerId, Candidate__c, Candidate__r.OwnerId, ' + phoneField +
                ' FROM Lead__c WHERE ' + phoneField + ' IN :phones';
            List<Lead__c> leadsByPhone = Database.query(leadSoql);
            for (Lead__c exLead : leadsByPhone) {
                String phone = (phoneField != null) ? String.valueOf(exLead.get(phoneField)) : null;
                if (String.isBlank(phone)) continue;
                String key = phone.trim();
                if (exLead.Student__c != null && exLead.Student__r != null && exLead.Student__r.OwnerId != null) {
                    if (!phoneToStudentOwner.containsKey(key)) {
                        phoneToStudentOwner.put(key, exLead.Student__r.OwnerId);
                    }
                } else if (exLead.Candidate__c != null && exLead.Candidate__r != null && exLead.Candidate__r.OwnerId != null) {
                    if (!phoneToCandidateOwner.containsKey(key)) {
                        phoneToCandidateOwner.put(key, exLead.Candidate__r.OwnerId);
                    }
                } else if (exLead.OwnerId != null) {
                    if (!phoneToLeadOwner.containsKey(key)) {
                        phoneToLeadOwner.put(key, exLead.OwnerId);
                    }
                }
            }
        }

        if (objectApiName == 'Lead__c' && !phones.isEmpty()) {
            List<Phone_Number__c> phoneLinks = [
                SELECT Phone__c, Candidate__r.OwnerId, Student__r.OwnerId, Lead__r.OwnerId
                FROM Phone_Number__c
                WHERE Phone__c IN :phones
            ];
            for (Phone_Number__c pn : phoneLinks) {
                if (String.isBlank(pn.Phone__c)) continue;
                String key = pn.Phone__c.trim();
                if (pn.Student__r != null && pn.Student__r.OwnerId != null) {
                    if (!phoneToStudentOwner.containsKey(key)) {
                        phoneToStudentOwner.put(key, pn.Student__r.OwnerId);
                    }
                } else if (pn.Candidate__r != null && pn.Candidate__r.OwnerId != null) {
                    if (!phoneToCandidateOwner.containsKey(key)) {
                        phoneToCandidateOwner.put(key, pn.Candidate__r.OwnerId);
                    }
                } else if (pn.Lead__r != null && pn.Lead__r.OwnerId != null) {
                    if (!phoneToLeadOwner.containsKey(key)) {
                        phoneToLeadOwner.put(key, pn.Lead__r.OwnerId);
                    }
                }
            }
        }

        if (objectApiName == 'Lead__c' && !emails.isEmpty()) {
            List<Email__c> emailLinks = [
                SELECT Email__c, Candidate__r.OwnerId, Student__r.OwnerId, Lead__r.OwnerId
                FROM Email__c
                WHERE Email__c IN :emails
            ];
            for (Email__c em : emailLinks) {
                if (String.isBlank(em.Email__c)) continue;
                String key = em.Email__c.trim().toLowerCase();
                if (em.Student__r != null && em.Student__r.OwnerId != null) {
                    if (!emailToStudentOwner.containsKey(key)) {
                        emailToStudentOwner.put(key, em.Student__r.OwnerId);
                    }
                } else if (em.Candidate__r != null && em.Candidate__r.OwnerId != null) {
                    if (!emailToCandidateOwner.containsKey(key)) {
                        emailToCandidateOwner.put(key, em.Candidate__r.OwnerId);
                    }
                } else if (em.Lead__r != null && em.Lead__r.OwnerId != null) {
                    if (!emailToLeadOwner.containsKey(key)) {
                        emailToLeadOwner.put(key, em.Lead__r.OwnerId);
                    }
                }
            }
        }

        List<SObject> forRoundRobin = new List<SObject>();
        Integer stickyAssigned = 0;

        for (SObject s : records) {
            Boolean assigned = false;

            if (objectApiName == 'Lead__c') {
                String courseVal = (courseField != null) ? String.valueOf(s.get(courseField)) : null;
                Boolean skipStudentOwner = (!String.isBlank(courseVal) && 'MCOM'.equalsIgnoreCase(courseVal));
                String phone = (phoneField != null) ? String.valueOf(s.get(phoneField)) : null;
                String email = String.valueOf(s.get('Email__c'));

                if (!skipStudentOwner && !String.isBlank(phone)) {
                    String key = phone.trim();
                    Id studentOwner = phoneToStudentOwner.get(key);
                    if (studentOwner != null) {
                        setAssignee(s, cfg.assignToField, studentOwner);
                        assigned = true;
                    } else {
                        Id candidateOwner = phoneToCandidateOwner.get(key);
                        Id leadOwner = phoneToLeadOwner.get(key);
                        if (candidateOwner != null) {
                            setAssignee(s, cfg.assignToField, candidateOwner);
                            assigned = true;
                        } else if (leadOwner != null) {
                            setAssignee(s, cfg.assignToField, leadOwner);
                            assigned = true;
                        }
                    }
                }

                if (!assigned && !skipStudentOwner && !String.isBlank(email)) {
                    String eKey = email.trim().toLowerCase();
                    Id studentOwner = emailToStudentOwner.get(eKey);
                    if (studentOwner != null) {
                        setAssignee(s, cfg.assignToField, studentOwner);
                        assigned = true;
                    } else {
                        Id candidateOwner = emailToCandidateOwner.get(eKey);
                        Id leadOwner = emailToLeadOwner.get(eKey);
                        if (candidateOwner != null) {
                            setAssignee(s, cfg.assignToField, candidateOwner);
                            assigned = true;
                        } else if (leadOwner != null) {
                            setAssignee(s, cfg.assignToField, leadOwner);
                            assigned = true;
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
