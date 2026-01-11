global class LeadEscalationScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        Database.executeBatch(new LeadEscalationBatch(), 200);
    }
}