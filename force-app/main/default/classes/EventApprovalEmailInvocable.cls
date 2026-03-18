public without sharing class EventApprovalEmailInvocable {

    public class Request {
        @InvocableVariable(required=true)
        public Id eventId;

        @InvocableVariable
        public Id leadId;
    }

    public class Result {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String message;
    }

    @InvocableMethod(
        label='Send Event Approval Email + Notification (Manager)'
        description='Loads template by DeveloperName, replaces tokens, and sends email +  notification.'
    )
    public static List<Result> send(List<Request> requests) {

        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;

        EmailTemplate tmpl = [
            SELECT Id, DeveloperName, Subject, HtmlValue, Body
            FROM EmailTemplate
            WHERE DeveloperName = 'Event_Approval_Request_Email'
            LIMIT 1
        ];

        Set<Id> eventIds = new Set<Id>();
        Set<Id> leadIds = new Set<Id>();

        for (Request r : requests) {
            if (r != null) {
                if (r.eventId != null) eventIds.add(r.eventId);
                if (r.leadId != null) leadIds.add(r.leadId);
            }
        }

        Map<Id, Event> evMap = new Map<Id, Event>([
            SELECT Id, Subject, StartDateTime, EndDateTime, Location, Description, WhoId, WhatId, OwnerId, Approval_Status__c
            FROM Event
            WHERE Id IN :eventIds
        ]);
        
        // Collect Event Owner Ids
        Set<Id> eventOwnerIds = new Set<Id>();
        for (Event e : evMap.values()) {
            if (e.OwnerId != null) {
                eventOwnerIds.add(e.OwnerId);
            }
        }
        
        // Query Event Owners
        Map<Id, User> eventOwnerMap = eventOwnerIds.isEmpty()
            ? new Map<Id, User>()
            : new Map<Id, User>([
                SELECT Id, Name, Email
                FROM User
                WHERE Id IN :eventOwnerIds
            ]);


        for (Event ev : evMap.values()) {
            if (ev.WhatId != null) {
                leadIds.add(ev.WhatId);
            }
        }

        Map<Id, Lead__c> leadMap = leadIds.isEmpty()
            ? new Map<Id, Lead__c>()
            : new Map<Id, Lead__c>([
                SELECT Id, Name, OwnerId
                FROM Lead__c
                WHERE Id IN :leadIds
            ]);

        Set<Id> ownerIds = new Set<Id>();
        for (Lead__c l : leadMap.values()) {
            if (l.OwnerId != null) ownerIds.add(l.OwnerId);
        }

        Map<Id, User> ownerUserMap = ownerIds.isEmpty()
            ? new Map<Id, User>()
            : new Map<Id, User>([
                SELECT Id, ManagerId
                FROM User
                WHERE Id IN :ownerIds
            ]);

        Set<Id> managerIds = new Set<Id>();
        for (User u : ownerUserMap.values()) {
            if (u.ManagerId != null) managerIds.add(u.ManagerId);
        }

        Map<Id, User> managerMap = managerIds.isEmpty()
            ? new Map<Id, User>()
            : new Map<Id, User>([
                SELECT Id, Email, Name
                FROM User
                WHERE Id IN :managerIds
            ]);

        String currentUserName = UserInfo.getName();

        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        List<PendingNotification> pendingNotifs = new List<PendingNotification>();

        for (Request r : requests) {
            Result out = new Result();
            try {
                if (r == null || r.eventId == null) {
                    out.success = false; out.message = 'eventId is required';
                    results.add(out); continue;
                }

                Event ev = evMap.get(r.eventId);
                if (ev == null) {
                    out.success = false; out.message = 'Event not found: ' + r.eventId;
                    results.add(out); continue;
                }
                
                User eventOwner = eventOwnerMap.get(ev.OwnerId);
                String eventOwnerName = eventOwner != null ? eventOwner.Name : '';

                String reviewUrl = URL.getOrgDomainUrl().toExternalForm()
                        + '/lightning/r/Event/' + ev.Id + '/view';
                
                // ======================================================
                // SEND EMAIL + NOTIFICATION TO EVENT OWNER (APPROVED / REJECTED)
                // ======================================================
                
                if (ev.OwnerId != null && (ev.Approval_Status__c == 'Approved' || ev.Approval_Status__c == 'Rejected') &&
                    eventOwner != null &&
                    !String.isBlank(eventOwner.Email)) {
                
                    EmailTemplate statusTemplate = [
                        SELECT Id, Subject, HtmlValue, Body
                        FROM EmailTemplate
                        WHERE DeveloperName = :(
                            ev.Approval_Status__c == 'Approved'
                            ? 'Event_Approval_Email_Template'
                            : 'Event_Rejection_Email_Template'
                        )
                        LIMIT 1
                    ];
                
                    //User eventOwner = eventOwnerMap.get(ev.OwnerId);

                
                    if (!String.isBlank(eventOwner.Email)) {
                
                        String reviewUrlOwner = URL.getOrgDomainUrl().toExternalForm()
                            + '/lightning/r/Event/' + ev.Id + '/view';
                
                        String subjectOwner = statusTemplate.Subject;
                        String htmlBodyOwner = statusTemplate.HtmlValue;
                        String textBodyOwner = statusTemplate.Body;
                        
                        //String eventOwnerName = eventOwner != null ? eventOwner.Name : '';
                
                        //subjectOwner = replaceTokens(subjectOwner, ev, reviewUrlOwner, '', currentUserName);
                        subjectOwner = replaceTokens(subjectOwner, ev, reviewUrlOwner, '', currentUserName, eventOwnerName);
                
                        if (!String.isBlank(htmlBodyOwner)) {
                            htmlBodyOwner = replaceTokens(htmlBodyOwner, ev, reviewUrlOwner, '', currentUserName, eventOwnerName);
                        }
                
                        if (!String.isBlank(textBodyOwner)) {
                            textBodyOwner = replaceTokens(textBodyOwner, ev, reviewUrlOwner, '', currentUserName, eventOwnerName);
                        }
                
                        Messaging.SingleEmailMessage ownerMail = new Messaging.SingleEmailMessage();
                        ownerMail.setToAddresses(new List<String>{ eventOwner.Email });
                        ownerMail.setSubject(subjectOwner);
                
                        if (!String.isBlank(htmlBodyOwner)) {
                            ownerMail.setHtmlBody(htmlBodyOwner);
                        } else {
                            ownerMail.setPlainTextBody(textBodyOwner);
                        }
                
                        ownerMail.setSaveAsActivity(false);
                        mails.add(ownerMail);
                
                        // Custom Notification for Event Owner
                        String ownerNotifTitle = 'Event ' + ev.Approval_Status__c;
                        String ownerNotifBody = 'Your event "' + ev.Subject +
                            '" has been ' + ev.Approval_Status__c + '. Click to review details.';
                
                        pendingNotifs.add(
                            new PendingNotification(ev.OwnerId, ev.Id, ownerNotifTitle, ownerNotifBody)
                        );
                    }

                    out.success = true;
                    out.message = 'Prepared';
                    results.add(out);
                    continue;
                }


                Lead__c leadRec = (r.leadId != null) ? leadMap.get(r.leadId) : null;
                if (leadRec == null && ev.WhatId != null) {
                    leadRec = leadMap.get(ev.WhatId);
                }
                if (leadRec == null || leadRec.OwnerId == null) {
                    Id leadRefId = (r.leadId != null) ? r.leadId : ev.WhatId;
                    out.success = false; out.message = 'Lead owner manager not found for lead: ' + leadRefId;
                    results.add(out); continue;
                }

                User ownerUser = ownerUserMap.get(leadRec.OwnerId);
                if (ownerUser == null || ownerUser.ManagerId == null) {
                    out.success = false; out.message = 'Lead owner manager not found for lead: ' + leadRec.Id;
                    results.add(out); continue;
                }

                User manager = managerMap.get(ownerUser.ManagerId);
                if (manager == null || String.isBlank(manager.Email)) {
                    out.success = false; out.message = 'Lead owner manager user not found or email blank: ' + ownerUser.ManagerId;
                    results.add(out); continue;
                }

                String leadName = '';
                if (leadRec != null) {
                    leadName = leadRec.Name;
                }

                //String reviewUrl = URL.getOrgDomainUrl().toExternalForm()
                  //  + '/lightning/r/Event/' + ev.Id + '/view';

                String subject = tmpl.Subject;
                String htmlBody = tmpl.HtmlValue;
                String textBody = tmpl.Body;

                subject = replaceTokens(subject, ev, reviewUrl, leadName, currentUserName, eventOwnerName);

                if (!String.isBlank(htmlBody)) {
                    htmlBody = replaceTokens(htmlBody, ev, reviewUrl, leadName, currentUserName, eventOwnerName);
                }
                if (!String.isBlank(textBody)) {
                    textBody = replaceTokens(textBody, ev, reviewUrl, leadName, currentUserName, eventOwnerName);
                }

                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ manager.Email });
                mail.setSubject(subject);

                if (!String.isBlank(htmlBody)) {
                    mail.setHtmlBody(htmlBody);
                } else {
                    mail.setPlainTextBody(textBody);
                }

                mail.setSaveAsActivity(false);
                mails.add(mail);

                String notifTitle = 'Gmeet Approval Request';
                String notifBody = 'Gmeet ' + (ev.Subject == null ? '' : ev.Subject)
                    + ' for Lead ' + leadName + '  requires approval.';
                pendingNotifs.add(new PendingNotification(manager.Id, ev.Id, notifTitle, notifBody));

                out.success = true;
                out.message = 'Prepared';
            } catch (Exception e) {
                out.success = false;
                out.message = e.getMessage();
            }
            results.add(out);
        }

        if (!mails.isEmpty()) {
            Messaging.sendEmail(mails, false);
        }

        sendCustomNotifications(pendingNotifs);

        return results;
    }

    private class PendingNotification {
        public Id recipientId;
        public Id targetId;
        public String title;
        public String body;

        public PendingNotification(Id recipientId, Id targetId, String title, String body) {
            this.recipientId = recipientId;
            this.targetId = targetId;
            this.title = title;
            this.body = body;
        }
    }

    private static void sendCustomNotifications(List<PendingNotification> pendingNotifs) {
        if (pendingNotifs == null || pendingNotifs.isEmpty()) return;

        Id notifTypeId;
        try {
            notifTypeId = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = 'Custom_Notification' OR MasterLabel = 'Custom Notification'
                LIMIT 1
            ].Id;
        } catch (Exception e) {
            return;
        }

        for (PendingNotification pn : pendingNotifs) {
            if (pn == null || pn.recipientId == null || pn.targetId == null) continue;
            Messaging.CustomNotification cn = new Messaging.CustomNotification();
            cn.setNotificationTypeId(notifTypeId);
            cn.setTitle(pn.title);
            cn.setBody(pn.body);
            cn.setSenderId(UserInfo.getUserId());
            cn.setTargetId(pn.targetId);
            cn.send(new Set<String>{ String.valueOf(pn.recipientId) });
        }
    }

    private static String replaceTokens(String input, Event ev, String reviewUrl, String leadName, String currentUserName, String eventOwnerName) {
        if (String.isBlank(input)) return input;

        String startStr = (ev.StartDateTime != null) ? String.valueOf(ev.StartDateTime) : '';
        String endStr   = (ev.EndDateTime != null) ? String.valueOf(ev.EndDateTime) : '';
        String whoVal   = (ev.WhoId != null) ? String.valueOf(ev.WhoId) : '';

        input = input.replace('{!Event.Subject}', ev.Subject == null ? '' : ev.Subject);
        input = input.replace('{!Event.StartDateTime}', startStr);
        input = input.replace('{!Event.EndDateTime}', endStr);
        input = input.replace('{!Event.Who}', whoVal);

        input = input.replace('{!Event.Location}', ev.Location == null ? '' : ev.Location);
        input = input.replace('{!Event.Description}', ev.Description == null ? '' : ev.Description);

        input = input.replace('{!Lead__c.Name}', String.isBlank(leadName) ? '' : leadName);
        input = input.replace('{!CurrentUserName}', String.isBlank(currentUserName) ? '' : currentUserName);

        input = input.replace('{ReviewUrl}', reviewUrl);
        input = input.replace('{!Event.OwnerName}', String.isBlank(eventOwnerName) ? '' : eventOwnerName);


        return input;
    }
}