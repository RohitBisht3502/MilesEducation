public class LoanUpdateTriggerHandler {

    public static void validateBeforeInsert(List<Loan__c> newLoans) {
        if (newLoans == null || newLoans.isEmpty()) return;

        applyCurrentAddressFromPermanent(newLoans);

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

   private static void applyCurrentAddressFromPermanent(List<Loan__c> newLoans) {
    for (Loan__c loan : newLoans) {
        if (loan.Current_Address_Same_As_Permanent__c == true) {

            loan.flat_no__c = loan.permanent_flat_no__c;
            loan.street__c = loan.permanent_street__c;
            loan.land_mark__c = loan.permanent_land_mark__c;
            loan.pincode__c = loan.permanent_pincode__c;
        }
    }
}


    @future(callout=true)
    public static void loanUpdate(List<Id> loanIds) {

        List<Loan__c> loans = [
            SELECT Id, Program_Name__c, First_Name__c, Email__c, Mobile__c, Amount_Requested__c,
                   Tenure__c, Gender__c, Marital_Status__c, Earning_Status__c, Occupation_Type__c,
                   Monthly_Income__c, Applying_Loan_For__c, Relationship_With_Applicant__c,
                   Current_Address_Same_As_Permanent__c, flat_no__c,
street__c,
land_mark__c,
pincode__c,
permanent_flat_no__c,
permanent_street__c,
permanent_land_mark__c,
permanent_pincode__c, PAN_Number__c, Date_of_Birth__c, State__c, City__c,
                   RecordType.DeveloperName
            FROM Loan__c
            WHERE Id IN :loanIds
        ];

        String endpoint = 'https://hn19ywvvng.execute-api.ap-south-1.amazonaws.com/Miles360/loan/create';
        String serviceName = 'Loan Creation API';

        Map<String, Schema.SObjectField> loanFieldMap =
            Loan__c.SObjectType.getDescribe().fields.getMap();

        String currentFlatField = getFirstExistingField(
            loanFieldMap,
            new List<String>{
                'Current_Flat_No__c',
                'Current_Flat_Number__c',
                'Current_House_No__c',
                'Current_House_Number__c'
            }
        );
        String currentLandmarkField = getFirstExistingField(
            loanFieldMap,
            new List<String>{
                'Current_Landmark__c',
                'Current_Land_Mark__c',
                'Current_Landmark_Name__c'
            }
        );
        String permanentFlatField = getFirstExistingField(
            loanFieldMap,
            new List<String>{
                'Permanent_Flat_No__c',
                'Permanent_Flat_Number__c',
                'Permanent_House_No__c',
                'Permanent_House_Number__c'
            }
        );
        String permanentLandmarkField = getFirstExistingField(
            loanFieldMap,
            new List<String>{
                'Permanent_Landmark__c',
                'Permanent_Land_Mark__c',
                'Permanent_Landmark_Name__c'
            }
        );

        for (Loan__c loan : loans) {

            String provider = loan.RecordType.DeveloperName;

            Map<String, Object> body = new Map<String, Object>{
                'loan_provider' => provider,
                'sf_id' => loan.Id,
                'program_name' => loan.Program_Name__c,
                'first_name' => loan.First_Name__c,
                'last_name' => loan.First_Name__c,
                'email' => loan.Email__c,
                'mobile' => loan.Mobile__c,
                'amount_requested' => loan.Amount_Requested__c
            };
            body.put('tenure', mapTenure(loan.Tenure__c));

            /* ================= AVANSE ================= */
            if (provider == 'AVANSE') {

                body.put(
                    'current_address_same_as_permanent',
                    loan.Current_Address_Same_As_Permanent__c
                );

             if (loan.Current_Address_Same_As_Permanent__c == true) {
    putPermanentAddress(body, loan);
} else {
    putCurrentAddress(body, loan);
    putPermanentAddress(body, loan);
}


                body.put('applying_loan_for', loan.Applying_Loan_For__c);

                body.put(
                    'earning_status',
                    mapEarningStatus(loan.Earning_Status__c)
                );

                body.put(
                    'occupation_type',
                    mapOccupation(loan.Occupation_Type__c)
                );

                body.put('monthly_income', loan.Monthly_Income__c);

                body.put(
                    'marital_status',
                    mapMaritalStatus(loan.Marital_Status__c)
                );

                body.put('gender', loan.Gender__c);
            }

            /* ================= PROPELLD ================= */
            else if (provider == 'PROPELLD') {

            }

            /* ================= AKSHAR ================= */
            else if (provider == 'AKSHAR') {

                body.put('pan_number', loan.PAN_Number__c);
                body.put('date_of_birth', String.valueOf(loan.Date_of_Birth__c));

                body.put(
    'address',
    String.join(
        new List<String>{
            loan.flat_no__c,
            loan.street__c
            
        },
        ', '
    )
);
 body.put('city', String.valueOf(loan.City__C));
  body.put('state', String.valueOf(loan.State__c));
body.put('pincode', loan.pincode__c);

                body.put('student_first_name', loan.First_Name__c);
                body.put('student_last_name', loan.First_Name__c);
            }

            /* ================= SEND ================= */

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('x-api-key', 'n7yno1N32NaXgZJFLbzf137wCHFf2UsM40j7gSgW');

            String requestPayload = truncate(JSON.serialize(body));
            req.setBody(requestPayload);

            Http http = new Http();

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

    private static void putCurrentAddress(
    Map<String, Object> body,
    Loan__c loan
) {
    body.put('flat_no', loan.flat_no__c);
    body.put('street', loan.street__c);
    body.put('land_mark', loan.land_mark__c);
    body.put('pincode', loan.pincode__c);
}


   private static void putPermanentAddress(
    Map<String, Object> body,
    Loan__c loan
) {
    body.put('permanent_flat_no', loan.permanent_flat_no__c);
    body.put('permanent_street', loan.permanent_street__c);
    body.put('permanent_land_mark', loan.permanent_land_mark__c);
    body.put('permanent_pincode', loan.permanent_pincode__c);
}


    private static String buildAddressLine(
        Loan__c loan,
        String flatField,
        String landmarkField
    ) {
        List<String> parts = new List<String>();
        String flat = getTextFieldValue(loan, flatField);
        String street = getTextFieldValue(loan, 'Current_Address__Street__s');
        String landmark = getTextFieldValue(loan, landmarkField);

        if (!String.isBlank(flat)) parts.add(flat);
        if (!String.isBlank(street)) parts.add(street);
        if (!String.isBlank(landmark)) parts.add(landmark);

        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    private static String getTextFieldValue(Loan__c loan, String fieldApi) {
        if (String.isBlank(fieldApi)) return null;
        Object value = loan.get(fieldApi);
        return value == null ? null : String.valueOf(value);
    }

    private static Integer mapTenure(String tenureVal) {
        if (tenureVal == null) return null;

        if (tenureVal.contains('3')) return 3;
        if (tenureVal.contains('6')) return 6;

        return null;
    }

    private static Integer mapEarningStatus(String val) {
        if (val == 'Earning') return 1;
        if (val == 'Not Earning') return 0;
        return null;
    }

    private static Integer mapOccupation(String val) {
        if (val == 'Salaried') return 1;
        if (val == 'Self Employed') return 2;
        return null;
    }

    private static String mapMaritalStatus(String val) {
        if (val == 'Single') return 'S';
        if (val == 'Married') return 'M';
        if (val == 'Divorced') return 'D';
        if (val == 'Other') return 'O';
        return null;
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