public with sharing class EventApprovalEmailInvocable {

    public class Request {
        @InvocableVariable(required=true)
        public Id eventId;

        @InvocableVariable(required=true)
        public Id recipientId;

        @InvocableVariable
        public Id leadId;
    }

    public class Result {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String message;
    }

    @InvocableMethod(
        label='Send Event Approval Email (Template + RecipientId)'
        description='Loads template by DeveloperName, replaces Event tokens, sends email to recipientId user. ReviewUrl auto-built from Event Id.'
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
        Set<Id> recipientIds = new Set<Id>();
        Set<Id> leadIds = new Set<Id>();

        for (Request r : requests) {
            if (r != null) {
                if (r.eventId != null) eventIds.add(r.eventId);
                if (r.recipientId != null) recipientIds.add(r.recipientId);
                if (r.leadId != null) leadIds.add(r.leadId);
            }
        }

        Map<Id, Event> evMap = new Map<Id, Event>([
            SELECT Id, Subject, StartDateTime, EndDateTime, Location, Description, WhoId, WhatId
            FROM Event
            WHERE Id IN :eventIds
        ]);

        Map<Id, User> userMap = new Map<Id, User>([
            SELECT Id, Email, Name
            FROM User
            WHERE Id IN :recipientIds
        ]);

        Map<Id, Lead__c> leadMap = leadIds.isEmpty()
            ? new Map<Id, Lead__c>()
            : new Map<Id, Lead__c>([
                SELECT Id, Name
                FROM Lead__c
                WHERE Id IN :leadIds
            ]);

        String currentUserName = UserInfo.getName();

        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();

        for (Request r : requests) {
            Result out = new Result();
            try {
                if (r == null || r.eventId == null) {
                    out.success = false; out.message = 'eventId is required';
                    results.add(out); continue;
                }
                if (r.recipientId == null) {
                    out.success = false; out.message = 'recipientId is required';
                    results.add(out); continue;
                }

                Event ev = evMap.get(r.eventId);
                if (ev == null) {
                    out.success = false; out.message = 'Event not found: ' + r.eventId;
                    results.add(out); continue;
                }

                User u = userMap.get(r.recipientId);
                if (u == null || String.isBlank(u.Email)) {
                    out.success = false; out.message = 'Recipient user not found or email blank: ' + r.recipientId;
                    results.add(out); continue;
                }

                String leadName = '';
                if (r.leadId != null && leadMap.containsKey(r.leadId)) {
                    leadName = leadMap.get(r.leadId).Name;
                }

                String reviewUrl = URL.getOrgDomainUrl().toExternalForm()
                    + '/lightning/r/Event/' + ev.Id + '/view';

                String subject = tmpl.Subject;
                String htmlBody = tmpl.HtmlValue;
                String textBody = tmpl.Body;

                subject = replaceTokens(subject, ev, reviewUrl, leadName, currentUserName);

                if (!String.isBlank(htmlBody)) {
                    htmlBody = replaceTokens(htmlBody, ev, reviewUrl, leadName, currentUserName);
                }
                if (!String.isBlank(textBody)) {
                    textBody = replaceTokens(textBody, ev, reviewUrl, leadName, currentUserName);
                }

                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ u.Email });
                mail.setSubject(subject);

                if (!String.isBlank(htmlBody)) {
                    mail.setHtmlBody(htmlBody);
                } else {
                    mail.setPlainTextBody(textBody);
                }

                mail.setSaveAsActivity(false);
                mails.add(mail);

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

        return results;
    }

    private static String replaceTokens(String input, Event ev, String reviewUrl, String leadName, String currentUserName) {
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

        return input;
    }
}