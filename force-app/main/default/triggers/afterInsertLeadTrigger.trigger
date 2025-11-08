trigger afterInsertLeadTrigger on Lead (after insert) {
/*  Set<Id> newLeadIds = new Set<Id>();

    for (Lead ld : Trigger.new) {
        newLeadIds.add(ld.Id);
    }

    //  Asynchronously update city for new leads
    if (!newLeadIds.isEmpty()) {
        LeadCityClassifier.enqueueLeadCityUpdate(newLeadIds);
    }

    // Enqueue Zoom Webinar Registration (only if lead has valid info)
    Set<Id> leadsForZoom = new Set<Id>();
    for (Lead ld : Trigger.new) {
        // Now using Phone + FirstName as mandatory fields
        if (String.isNotBlank(ld.Phone) && String.isNotBlank(ld.FirstName)) {
            leadsForZoom.add(ld.Id);
        }
    }

    if (!leadsForZoom.isEmpty()) {
        System.enqueueJob(new LeadZoomRegistrationJob(leadsForZoom));
    } */
}