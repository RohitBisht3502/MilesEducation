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

        Set<String> phones  = new Set<String>();
        Set<String> sources = new Set<String>();

        if (cfg.enableSticky) {
            for (SObject s : records) {
                String phone = (phoneField != null) ? String.valueOf(s.get(phoneField)) : null;
                String src   = (sourceField != null) ? String.valueOf(s.get(sourceField)) : null;

                if (!String.isBlank(phone)) phones.add(phone.trim());
                if (!String.isBlank(src)) sources.add(src.trim());
            }
        }

        Map<String, Id> phoneSourceToUser = new Map<String, Id>();
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

        List<SObject> forRoundRobin = new List<SObject>();
        Integer stickyAssigned = 0;

        for (SObject s : records) {
            Boolean assigned = false;

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