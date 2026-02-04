public class LoanUpdateTriggerHandler {
    public static void validateBeforeInsert(List<Loan__c> newLoans) {
        if (newLoans == null || newLoans.isEmpty()) return;

        Map<String, Schema.SObjectField> loanFieldMap =
            Loan__c.SObjectType.getDescribe().fields.getMap();

        String candidateField = getFirstExistingField(
            loanFieldMap,
            new List<String>{ 'Candidate__c', 'Candidate_Id__c' }
        );
        String courseField = getFirstExistingField(
            loanFieldMap,
            new List<String>{ 'Program_Name__c', 'Course__c' }
        );
        String loanLeadTagField = getFirstExistingField(
            loanFieldMap,
            new List<String>{ 'Lead__c', 'Lead_Lookup__c' }
        );

        if (String.isBlank(candidateField) || String.isBlank(courseField)) return;

        Set<Id> candidateIds = new Set<Id>();
        Set<String> courses = new Set<String>();

        for (Loan__c loan : newLoans) {
            Id candId = (Id) loan.get(candidateField);
            String course = (String) loan.get(courseField);
            if (candId != null && !String.isBlank(course)) {
                candidateIds.add(candId);
                courses.add(course.trim());
            }
        }

        if (candidateIds.isEmpty() || courses.isEmpty()) return;

        Map<String, List<Lead__c>> leadsByCandidateCourse = new Map<String, List<Lead__c>>();
        for (Lead__c leadRec : [
            SELECT Id, Candidate__c, Course__c, Stage__c
            FROM Lead__c
            WHERE Candidate__c IN :candidateIds
              AND Course__c IN :courses
        ]) {
            String key = buildCandidateCourseKey(leadRec.Candidate__c, leadRec.Course__c);
            if (!leadsByCandidateCourse.containsKey(key)) {
                leadsByCandidateCourse.put(key, new List<Lead__c>());
            }
            leadsByCandidateCourse.get(key).add(leadRec);
        }

        for (Loan__c loan : newLoans) {
            Id candId = (Id) loan.get(candidateField);
            String course = (String) loan.get(courseField);
            if (candId == null || String.isBlank(course)) continue;

            String key = buildCandidateCourseKey(candId, course);
            List<Lead__c> matchingLeads = leadsByCandidateCourse.get(key);

            if (matchingLeads == null || matchingLeads.isEmpty()) {
                loan.addError('Lead not exist with this course for selected Candidate.');
                continue;
            }

            Lead__c m7Lead = null;
            for (Lead__c leadRec : matchingLeads) {
                if (isM7Stage(leadRec.Stage__c)) {
                    m7Lead = leadRec;
                    break;
                }
            }

            if (m7Lead == null) {
                loan.addError('Not eligible for loan. Stage is not in M7 for this course lead.');
                continue;
            }

            if (!String.isBlank(loanLeadTagField)) {
                loan.put(loanLeadTagField, m7Lead.Id);
            }
        }
    }

    @future(callout=true)
    public static void loanUpdate(List<Id> loanIds) {

        List<Loan__c> loans = [
            SELECT Id, Program_Name__c, First_Name__c,
                   Email__c, Mobile__c, Amount_Requested__c, Tenure__c,
                   Gender__c, Marital_Status__c, Earning_Status__c,
                   Occupation_Type__c, Monthly_Income__c,
                   Applying_Loan_For__c, Relationship_With_Applicant__c,
                   Current_Address__c, Current_Address_Same_As_Permanent__c
            FROM Loan__c
            WHERE Id IN :loanIds
        ];

        String endpoint = 'https://hn19ywvvng.execute-api.ap-south-1.amazonaws.com/Miles360/loan/create';
        String serviceName = 'Loan Creation API';

        for (Loan__c loan : loans) {

            Http http = new Http();
            HttpRequest req = new HttpRequest();

            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('x-api-key', 'n7yno1N32NaXgZJFLbzf137wCHFf2UsM40j7gSgW');

            Map<String, Object> body = new Map<String, Object>{
                'program_name' => loan.Program_Name__c,
                'first_name' => loan.First_Name__c,
                'email' => loan.Email__c,
                'mobile' => loan.Mobile__c,
                'amount_requested' => loan.Amount_Requested__c,
                'tenure' => loan.Tenure__c,
                'gender' => loan.Gender__c,
                'marital_status' => loan.Marital_Status__c,
                'earning_status' => loan.Earning_Status__c,
                'occupation_type' => loan.Occupation_Type__c,
                'monthly_income' => loan.Monthly_Income__c,
                'applying_loan_for' => loan.Applying_Loan_For__c,
                'relationship_with_applicant' => loan.Relationship_With_Applicant__c,
                'current_address' => loan.Current_Address__c,
                'current_address_same_as_permanent' => loan.Current_Address_Same_As_Permanent__c
            };

            String requestPayload = truncate(JSON.serialize(body));
            req.setBody(requestPayload);

            try {
                HttpResponse res = http.send(req);

                String responsePayload = truncate(res.getBody());

                if (res.getStatusCode() == 200) {
                    IntegrationLogUtil.insertLog(
                        serviceName,
                        requestPayload,
                        responsePayload,
                        'Loan created successfully',
                        'Success',
                        200
                    );
                } else {
                    IntegrationLogUtil.insertLog(
                        serviceName,
                        requestPayload,
                        responsePayload,
                        'Vendor API error',
                        'Failed',
                        res.getStatusCode()
                    );
                }

            } catch (Exception e) {
                IntegrationLogUtil.insertLog(
                    serviceName,
                    requestPayload,
                    null,
                    e.getMessage(),
                    'Failed',
                    500
                );
            }
        }
    }

    private static String truncate(String value) {
        return (value != null && value.length() > 3000)
            ? value.substring(0, 3000)
            : value;
    }

    private static String getFirstExistingField(
        Map<String, Schema.SObjectField> fieldMap,
        List<String> candidates
    ) {
        for (String fieldApi : candidates) {
            if (fieldMap.containsKey(fieldApi)) {
                return fieldApi;
            }
        }
        return null;
    }

    private static String buildCandidateCourseKey(Id candidateId, String course) {
        return String.valueOf(candidateId) + '|' + String.valueOf(course).trim();
    }

    private static Boolean isM7Stage(String stageVal) {
        if (String.isBlank(stageVal)) return false;
        String normalized = stageVal.trim().toUpperCase();
        return normalized == 'M7' || normalized.startsWith('M7');
    }
}
