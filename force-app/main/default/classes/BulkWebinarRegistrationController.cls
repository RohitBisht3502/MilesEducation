public with sharing class BulkWebinarRegistrationController {

    private ApexPages.StandardSetController ssc;

    public List<Id> leadIds { get; private set; }
    public Id selectedWebinarId { get; set; }

    public BulkWebinarRegistrationController(ApexPages.StandardSetController controller) {

        this.ssc = controller;
        leadIds = new List<Id>();

        List<SObject> selected = controller.getSelected();

        if (selected != null && !selected.isEmpty()) {
            for (SObject s : selected) {
                leadIds.add((Id)s.get('Id'));
            }
        }
    }

   
    public List<SelectOption> getWebinarOptions() {

        List<SelectOption> options = new List<SelectOption>();
        options.add(new SelectOption('', '-- Select Webinar --'));

        for (Webinar__c w : [
            SELECT Id, Name
            FROM Webinar__c
            WHERE IsActive__c = TRUE
            AND Status__c IN ('Created','Started')
            ORDER BY Start_Date_Time__c DESC
            LIMIT 200
        ]) {
            options.add(new SelectOption(w.Id, w.Name));
        }

        return options;
    }


  public PageReference registerLeads() {

    if (leadIds.isEmpty()) {
        ApexPages.addMessage(new ApexPages.Message(
            ApexPages.Severity.ERROR,
            'Please select at least one Lead.'
        ));
        return null;
    }

    if (selectedWebinarId == null) {
        ApexPages.addMessage(new ApexPages.Message(
            ApexPages.Severity.ERROR,
            'Please select a Webinar.'
        ));
        return null;
    }

    List<Lead__c> leads = [
        SELECT Id, Email__c
        FROM Lead__c
        WHERE Id IN :leadIds
    ];

    Set<Id> validLeadIds = new Set<Id>();

    for (Lead__c ld : leads) {
        if (String.isNotBlank(ld.Email__c)) {
            validLeadIds.add(ld.Id);
        }
    }

    if (validLeadIds.isEmpty()) {
        ApexPages.addMessage(new ApexPages.Message(
            ApexPages.Severity.ERROR,
            'None of the selected Leads have Email.'
        ));
        return null;
    }

    // Optional: log bulk trigger
    IntegrationLogUtil.insertLogs(new List<Integration_Log__c>{
        IntegrationLogUtil.buildLog(
            'Bulk Zoom Registration Trigger',
            'LeadIds=' + JSON.serialize(validLeadIds) +
            ', WebinarId=' + selectedWebinarId,
            null,
            null,
            'QUEUED',
            202
        )
    });

   Database.executeBatch(
    new LeadZoomRegistrationBatch(validLeadIds, new Set<Id>{ selectedWebinarId }),
    20
);

    ApexPages.addMessage(new ApexPages.Message(
        ApexPages.Severity.CONFIRM,
        'Registration started for ' + validLeadIds.size() + ' Leads.'
    ));

    return new PageReference('/lightning/o/Lead__c/list');
}
}