public with sharing class SObjectChangeOwnerController {

    private ApexPages.StandardSetController ssc;

    public List<Id> recordIds { get; private set; }
    public Id selectedUserId { get; set; }
    public String changeReason { get; set; }
    public String objectApiName { get; private set; }

    public SObjectChangeOwnerController(ApexPages.StandardSetController controller) {
        System.debug(LoggingLevel.INFO, 'SObjectChangeOwnerController :: Constructor START');

        this.ssc = controller;
        recordIds = new List<Id>();

        List<SObject> selected = controller.getSelected();
        System.debug(LoggingLevel.DEBUG, 'Selected records size: ' + (selected != null ? selected.size() : 0));

        if (selected != null && !selected.isEmpty()) {
            objectApiName = selected[0].getSObjectType().getDescribe().getName();
            for (SObject s : selected) {
                recordIds.add((Id)s.get('Id'));
            }
        }

        System.debug(LoggingLevel.INFO, 'Object API Name: ' + objectApiName);
        System.debug(LoggingLevel.INFO, 'Record Ids: ' + recordIds);
    }

    public List<SelectOption> getUsers() {
        System.debug(LoggingLevel.DEBUG, 'getUsers :: Fetching active users');

        List<SelectOption> opts = new List<SelectOption>();
        opts.add(new SelectOption('', '-- Select User --'));

        for (User u : [SELECT Id, Name FROM User WHERE IsActive = true ORDER BY Name]) {
            opts.add(new SelectOption(u.Id, u.Name));
        }
        return opts;
    }

    public PageReference updateOwner() {

        System.debug(LoggingLevel.INFO, 'updateOwner :: START');
        System.debug(LoggingLevel.DEBUG, 'Selected UserId: ' + selectedUserId);
        System.debug(LoggingLevel.DEBUG, 'Reason: ' + changeReason);
        System.debug(LoggingLevel.DEBUG, 'RecordIds: ' + recordIds);

        // No records selected
        if (recordIds == null || recordIds.isEmpty()) {
            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    'Please select at least one record from the list view.'
                )
            );
            System.debug(LoggingLevel.WARN, 'updateOwner :: No records selected');
            return null;
        }

        // No user selected
        if (selectedUserId == null) {
            ApexPages.addMessage(
                new ApexPages.Message(ApexPages.Severity.ERROR, 'Please select a user.')
            );
            System.debug(LoggingLevel.WARN, 'updateOwner :: No user selected');
            return null;
        }

        // No reason
        if (String.isBlank(changeReason)) {
            ApexPages.addMessage(
                new ApexPages.Message(ApexPages.Severity.ERROR, 'Please provide a reason.')
            );
            System.debug(LoggingLevel.WARN, 'updateOwner :: Reason is blank');
            return null;
        }

        String soql = 'SELECT Id, OwnerId FROM ' + objectApiName + ' WHERE Id IN :recordIds';
        System.debug(LoggingLevel.DEBUG, 'SOQL: ' + soql);

        List<SObject> records = Database.query(soql);
        System.debug(LoggingLevel.INFO, 'Records fetched: ' + records.size());

        List<Activity_Log__c> logs = new List<Activity_Log__c>();

        for (SObject rec : records) {
            Id oldOwnerId = (Id)rec.get('OwnerId');

            System.debug(LoggingLevel.DEBUG,
                'Updating record ' + rec.get('Id') +
                ' OldOwner=' + oldOwnerId +
                ' NewOwner=' + selectedUserId
            );

            // Update owner
            rec.put('OwnerId', selectedUserId);

            // Create activity log
            Activity_Log__c log = new Activity_Log__c();
            log.Name                   = objectApiName + ' Owner Change';
            log.Logging_Id__c          = UserInfo.getUserId();
            log.Activity_Type__c       = 'Owner Change';
            log.Created_By__c          = oldOwnerId;
            log.Action_Performed_By__c = UserInfo.getUserId();
            log.Changed_Date_Time__c   = System.now();
            log.Description__c =
                'Owner changed from ' + oldOwnerId +
                ' to ' + selectedUserId +
                '. Reason: ' + changeReason;

            logs.add(log);
        }

        update records;
        System.debug(LoggingLevel.INFO, 'Records updated successfully');

        if (!logs.isEmpty()) {
            insert logs;
            System.debug(LoggingLevel.INFO, 'Activity logs inserted: ' + logs.size());
        }

        System.debug(LoggingLevel.INFO, 'updateOwner :: END');
        return new PageReference('/lightning/o/' + objectApiName + '/list');
    }
}