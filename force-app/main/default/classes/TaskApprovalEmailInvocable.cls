public without sharing class TaskApprovalEmailInvocable {

    public class Request {
        @InvocableVariable(required=true)
        public Id taskId;
    }

    public class Result {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String message;
    }

    @InvocableMethod(
        label='Send Task Escalation Email + Notification'
        description='Loads template by DeveloperName and sends email + custom notification to Task Owner Manager.'
    )
    public static List<Result> send(List<Request> requests) {

        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;

        // 🔹 Load Email Template
        EmailTemplate tmpl = [
            SELECT Id, DeveloperName, Subject, HtmlValue, Body
            FROM EmailTemplate
            WHERE DeveloperName = 'Task_Email_Template'
            LIMIT 1
        ];

        Set<Id> taskIds = new Set<Id>();
        for (Request r : requests) {
            if (r != null && r.taskId != null) {
                taskIds.add(r.taskId);
            }
        }

        Map<Id, Task> taskMap = new Map<Id, Task>([
            SELECT Id, Subject, OwnerId, CreatedDate, ActivityDate
            FROM Task
            WHERE Id IN :taskIds
        ]);

        Set<Id> ownerIds = new Set<Id>();
        for (Task t : taskMap.values()) {
            if (t.OwnerId != null) ownerIds.add(t.OwnerId);
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

        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        List<PendingNotification> pendingNotifs = new List<PendingNotification>();

        for (Request r : requests) {
            Result out = new Result();
            try {

                if (r == null || r.taskId == null) {
                    out.success = false;
                    out.message = 'taskId is required';
                    results.add(out);
                    continue;
                }

                Task t = taskMap.get(r.taskId);
                if (t == null) {
                    out.success = false;
                    out.message = 'Task not found: ' + r.taskId;
                    results.add(out);
                    continue;
                }

                User ownerUser = ownerUserMap.get(t.OwnerId);
                if (ownerUser == null || ownerUser.ManagerId == null) {
                    out.success = false;
                    out.message = 'Task Owner Manager not found';
                    results.add(out);
                    continue;
                }

                User manager = managerMap.get(ownerUser.ManagerId);
                if (manager == null || String.isBlank(manager.Email)) {
                    out.success = false;
                    out.message = 'Manager email not found';
                    results.add(out);
                    continue;
                }

                String reviewUrl = URL.getOrgDomainUrl().toExternalForm()
                    + '/lightning/r/Task/' + t.Id + '/view';

                String subject = replaceTokens(tmpl.Subject, t, reviewUrl);
                String htmlBody = replaceTokens(tmpl.HtmlValue, t, reviewUrl);
                String textBody = replaceTokens(tmpl.Body, t, reviewUrl);

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

                // 🔔 Custom Notification
                pendingNotifs.add(new PendingNotification(
                    manager.Id,
                    t.Id,
                    'Task Review',
                    'Task "' + t.Subject + '" requires your attention.'
                ));

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
                WHERE DeveloperName = 'Custom_Notification'
                OR MasterLabel = 'Custom Notification'
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

    private static String replaceTokens(String input, Task t, String reviewUrl) {
        if (String.isBlank(input)) return input;

        input = input.replace('{!Task.Subject}', t.Subject == null ? '' : t.Subject);
        input = input.replace('{!Task.CreatedDate}', String.valueOf(t.CreatedDate));
        //input = input.replace('{!Task.ActivityDate}', String.valueOf(t.ActivityDate));
        input = input.replace('{ReviewUrl}', reviewUrl);

        return input;
    }
}