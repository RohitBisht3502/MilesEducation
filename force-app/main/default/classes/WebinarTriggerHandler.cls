/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class WebinarTriggerHandler {

    public static void beforeInsert(List<Webinar__c> newList) {}
    public static void beforeUpdate(List<Webinar__c> newList, Map<Id, Webinar__c> oldMap) {}
    public static void beforeDelete(List<Webinar__c> oldList) {}

    public static void afterInsert(List<Webinar__c> newList) {}

    public static void afterEndGetAttendanceData(List<Webinar__c> newList, Map<Id, Webinar__c> oldMap) {

        System.debug(LoggingLevel.INFO, 'WebinarTriggerHandler.afterUpdate START | newList size=' + (newList == null ? 0 : newList.size()));

        if (newList == null || newList.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'afterUpdate EXIT | newList/oldMap empty');
            return;
        }

        Set<Id> webinarIdsToSync = new Set<Id>();

        for (Webinar__c w : newList) {
            Webinar__c oldW = oldMap.get(w.Id);
            if (w == null || oldW == null) continue;

            if (w.Status__c == 'Ended' && oldW.Status__c != 'Ended' && !String.isBlank(w.Webinar_Id__c)) {
                webinarIdsToSync.add(w.Id);
            }
        }

        System.debug(LoggingLevel.INFO, 'afterUpdate | status->End webinars=' + webinarIdsToSync.size() + ' | ids=' + webinarIdsToSync);

        if (!webinarIdsToSync.isEmpty()) {
            WebinarLiveAttendanceSyncService.enqueueSync(webinarIdsToSync);
        }

        System.debug(LoggingLevel.INFO, 'WebinarTriggerHandler.afterUpdate END');
    }

    public static void updateWebinarMemberFieldsOnWebinarStart(List<Webinar__c> newList, Map<Id, Webinar__c> oldMap) {
        System.debug(LoggingLevel.INFO, 'updateWebinarMemberFieldsOnWebinarStart START');

        try {
            if (newList == null || newList.isEmpty() || oldMap == null) {
                System.debug(LoggingLevel.WARN, 'Inputs empty, exiting');
                return;
            }

            Set<Id> startedWebinarIds = new Set<Id>();
            for (Webinar__c w : newList) {
                Webinar__c oldW = oldMap.get(w.Id);
                if (oldW == null) continue;

                if (w.Status__c == 'Started' && oldW.Status__c != 'Started') {
                    startedWebinarIds.add(w.Id);
                }
            }

            System.debug(LoggingLevel.INFO, 'Started webinars count = ' + startedWebinarIds.size());
            if (startedWebinarIds.isEmpty()) return;

            List<Webinar_Member__c> members = [
                SELECT Id, Webinar__c, Lead__c
                FROM Webinar_Member__c
                WHERE Webinar__c IN :startedWebinarIds
            ];
            System.debug(LoggingLevel.INFO, 'Webinar members fetched = ' + members.size());
            if (members.isEmpty()) return;

            Set<Id> leadIds = new Set<Id>();
            for (Webinar_Member__c wm : members) {
                if (wm.Lead__c != null) leadIds.add(wm.Lead__c);
            }
            System.debug(LoggingLevel.INFO, 'Related Lead ids count = ' + leadIds.size());

            Map<Id, Lead__c> leadMap = new Map<Id, Lead__c>();
            if (!leadIds.isEmpty()) {
                leadMap = new Map<Id, Lead__c>([
                    SELECT Id, Stage__c, OwnerId
                    FROM Lead__c
                    WHERE Id IN :leadIds
                ]);
            }
            System.debug(LoggingLevel.INFO, 'Lead map size = ' + leadMap.size());

            List<Webinar_Member__c> toUpdate = new List<Webinar_Member__c>();
            for (Webinar_Member__c wm : members) {
                Lead__c l = (wm.Lead__c != null) ? leadMap.get(wm.Lead__c) : null;
                if (l == null) continue;

                Webinar_Member__c upd = new Webinar_Member__c(Id = wm.Id);
                upd.Lead_Owner_During_Webinar__c = l.OwnerId;
                upd.Lead_Stage_During_Webinar__c = l.Stage__c;

                toUpdate.add(upd);
            }

            System.debug(LoggingLevel.INFO, 'Members to update = ' + toUpdate.size());
            if (!toUpdate.isEmpty()) update toUpdate;

            System.debug(LoggingLevel.INFO, 'updateWebinarMemberFieldsOnWebinarStart END SUCCESS');

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'updateWebinarMemberFieldsOnWebinarStart ERROR: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, e.getStackTraceString());
        }
    }
    
    public static void afterDelete(List<Webinar__c> oldList) {}
    public static void afterUndelete(List<Webinar__c> newList) {}
}