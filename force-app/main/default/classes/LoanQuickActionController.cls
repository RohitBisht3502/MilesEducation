public with sharing class LoanQuickActionController {
    public class ValidationResult {
        @AuraEnabled public Boolean isValid;
        @AuraEnabled public String message;

        public ValidationResult(Boolean isValid, String message) {
            this.isValid = isValid;
            this.message = message;
        }
    }

    public class RecordTypeOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String developerName;

        public RecordTypeOption(String label, String value, String developerName) {
            this.label = label;
            this.value = value;
            this.developerName = developerName;
        }
    }

    public class InitData {
        @AuraEnabled public List<RecordTypeOption> recordTypes;
        @AuraEnabled public Map<String, Object> prefillValues;
        @AuraEnabled public String candidateFieldApi;
        @AuraEnabled public String courseFieldApi;
        @AuraEnabled public String leadLookupFieldApi;
        @AuraEnabled public String emailFieldApi;
        @AuraEnabled public String mobileFieldApi;
    }

    public class LayoutResponse {
        @AuraEnabled public List<LayoutSectionDTO> sections;
    }

    public class LayoutSectionDTO {
        @AuraEnabled public String heading;
        @AuraEnabled public List<LayoutRowDTO> rows;
    }

    public class LayoutRowDTO {
        @AuraEnabled public List<LayoutColDTO> cols;
    }

    public class LayoutColDTO {
        @AuraEnabled public String fieldApiName;
    }

    @AuraEnabled
    public static ValidationResult validateLeadCandidateCourse(Id candidateId, String course) {
        System.debug('LoanQuickActionController.validateLeadCandidateCourse candidateId=' + candidateId + ' course=' + course);
        if (candidateId == null || String.isBlank(course)) {
            System.debug('Validation skipped: candidateId or course is blank.');
            return new ValidationResult(true, null);
        }

        List<Lead__c> leads = [
            SELECT Id
            FROM Lead__c
            WHERE Candidate__c = :candidateId
              AND Course__c = :course
            LIMIT 1
        ];

        if (leads.isEmpty()) {
            System.debug('Validation failed: no Lead__c found for candidate + course.');
            return new ValidationResult(false, 'Lead not exist with this course for selected Candidate.');
        }

        System.debug('Validation passed: Lead__c exists.');
        return new ValidationResult(true, null);
    }

    @AuraEnabled(cacheable=true)
    public static InitData getInitData(Id leadId) {
        System.debug('LoanQuickActionController.getInitData leadId=' + leadId);
        InitData data = new InitData();
        data.recordTypes = new List<RecordTypeOption>();
        data.prefillValues = new Map<String, Object>();

        Schema.DescribeSObjectResult loanDescribe = Loan__c.SObjectType.getDescribe();
        Map<Id, Schema.RecordTypeInfo> rtInfos = loanDescribe.getRecordTypeInfosById();
        System.debug('RecordType count=' + rtInfos.size());
        for (Id rtId : rtInfos.keySet()) {
            Schema.RecordTypeInfo info = rtInfos.get(rtId);
            if (info != null && info.isAvailable() && !info.isMaster()) {
                System.debug('RecordType available: ' + info.getDeveloperName() + ' (' + info.getName() + ')');
                data.recordTypes.add(new RecordTypeOption(info.getName(), String.valueOf(rtId), info.getDeveloperName()));
            }
        }


        Map<String, Schema.SObjectField> fieldMap = loanDescribe.fields.getMap();
        data.candidateFieldApi = getFirstExistingField(fieldMap, new List<String>{ 'Candidate__c', 'Candidate_Id__c' });
        data.courseFieldApi = getFirstExistingField(fieldMap, new List<String>{ 'Program_Name__c', 'Course__c' });
        data.leadLookupFieldApi = getFirstExistingField(fieldMap, new List<String>{ 'Lead__c', 'Lead_Lookup__c' });
        data.emailFieldApi = getFirstExistingField(fieldMap, new List<String>{ 'Email__c' });
        data.mobileFieldApi = getFirstExistingField(fieldMap, new List<String>{ 'Mobile__c', 'Phone__c' });
        System.debug('Field mapping candidate=' + data.candidateFieldApi + ' course=' + data.courseFieldApi +
            ' leadLookup=' + data.leadLookupFieldApi + ' email=' + data.emailFieldApi + ' mobile=' + data.mobileFieldApi);

        Schema.DescribeSObjectResult leadDescribe = Lead__c.SObjectType.getDescribe();
        Map<String, Schema.SObjectField> leadFieldMap = leadDescribe.fields.getMap();
        String leadCandidateField = getFirstExistingField(leadFieldMap, new List<String>{ 'Candidate__c', 'Candidate_Id__c' });
        String leadCourseField = getFirstExistingField(leadFieldMap, new List<String>{ 'Program_Name__c', 'Course__c' });
        String leadEmailField = getFirstExistingField(leadFieldMap, new List<String>{ 'Email__c' });
        String leadMobileField = getFirstExistingField(leadFieldMap, new List<String>{ 'Mobile__c', 'Phone__c' });
        String leadNameField = getFirstExistingField(leadFieldMap, new List<String>{ 'First_Name__c', 'Name' });

        if (leadId != null) {
            List<String> leadFieldsToQuery = new List<String>{ 'Id' };
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadCandidateField);
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadCourseField);
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadEmailField);
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadMobileField);
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadNameField);

            String leadSoql = 'SELECT ' + String.join(leadFieldsToQuery, ',') + ' FROM Lead__c WHERE Id = :leadId LIMIT 1';
            Lead__c leadRec = Database.query(leadSoql);

            Id leadCandidateId = (Id) (leadCandidateField != null ? leadRec.get(leadCandidateField) : null);
            String leadCourseValue = getTextValue(leadRec, leadCourseField);
            String leadEmailValue = getTextValue(leadRec, leadEmailField);
            String leadMobileValue = getTextValue(leadRec, leadMobileField);
            String leadNameValue = getTextValue(leadRec, leadNameField);

            if (data.candidateFieldApi != null && leadCandidateId != null) {
                data.prefillValues.put(data.candidateFieldApi, leadCandidateId);
            }
            if (data.courseFieldApi != null && !String.isBlank(leadCourseValue)) {
                data.prefillValues.put(data.courseFieldApi, leadCourseValue);
            }
            if (data.leadLookupFieldApi != null) {
                data.prefillValues.put(data.leadLookupFieldApi, leadRec.Id);
            }
            if (data.emailFieldApi != null && !String.isBlank(leadEmailValue)) {
                data.prefillValues.put(data.emailFieldApi, leadEmailValue);
            }
            if (data.mobileFieldApi != null && !String.isBlank(leadMobileValue)) {
                data.prefillValues.put(data.mobileFieldApi, leadMobileValue);
            }

            String loanFirstNameField = getFirstExistingField(fieldMap, new List<String>{ 'First_Name__c' });
            if (!String.isBlank(loanFirstNameField) && !String.isBlank(leadNameValue)) {
                data.prefillValues.put(loanFirstNameField, leadNameValue);
            }

            Id candidateId = leadCandidateId;
            if (candidateId != null) {
                populateCandidateAddressPrefill(data.prefillValues, fieldMap, candidateId);
            }

            System.debug('Prefill values: ' + data.prefillValues);
        }

        return data;
    }

    @AuraEnabled
    public static Id createLoan(Id leadId, Id recordTypeId, Map<String, Object> fields) {
        if (fields == null) fields = new Map<String, Object>();

        Schema.DescribeSObjectResult loanDescribe = Loan__c.SObjectType.getDescribe();
        Map<String, Schema.SObjectField> loanFieldMap = loanDescribe.fields.getMap();
        Map<String, String> loanLowerMap = new Map<String, String>();
        for (String api : loanFieldMap.keySet()) {
            loanLowerMap.put(api.toLowerCase(), api);
        }

        Loan__c loan = new Loan__c();
        if (recordTypeId != null) {
            loan.RecordTypeId = recordTypeId;
        }

        for (String key : fields.keySet()) {
            if (String.isBlank(key)) continue;
            String api = loanLowerMap.containsKey(key.toLowerCase())
                ? loanLowerMap.get(key.toLowerCase())
                : key;
            if (!loanFieldMap.containsKey(api)) continue;
            loan.put(api, fields.get(key));
        }

        if (leadId != null) {
            Schema.DescribeSObjectResult leadDescribe = Lead__c.SObjectType.getDescribe();
            Map<String, Schema.SObjectField> leadFieldMap = leadDescribe.fields.getMap();
            String leadCandidateField = getFirstExistingField(leadFieldMap, new List<String>{ 'Candidate__c', 'Candidate_Id__c' });
            String leadCourseField = getFirstExistingField(leadFieldMap, new List<String>{ 'Program_Name__c', 'Course__c' });
            String leadEmailField = getFirstExistingField(leadFieldMap, new List<String>{ 'Email__c' });
            String leadMobileField = getFirstExistingField(leadFieldMap, new List<String>{ 'Mobile__c', 'Phone__c' });
            String leadNameField = getFirstExistingField(leadFieldMap, new List<String>{ 'First_Name__c', 'Name' });

            List<String> leadFieldsToQuery = new List<String>{ 'Id' };
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadCandidateField);
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadCourseField);
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadEmailField);
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadMobileField);
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadNameField);

            String leadSoql = 'SELECT ' + String.join(leadFieldsToQuery, ',') + ' FROM Lead__c WHERE Id = :leadId LIMIT 1';
            Lead__c leadRec = Database.query(leadSoql);

            String candidateField = getFirstExistingField(loanFieldMap, new List<String>{ 'Candidate__c', 'Candidate_Id__c' });
            String courseField = getFirstExistingField(loanFieldMap, new List<String>{ 'Program_Name__c', 'Course__c' });
            String emailField = getFirstExistingField(loanFieldMap, new List<String>{ 'Email__c' });
            String mobileField = getFirstExistingField(loanFieldMap, new List<String>{ 'Mobile__c', 'Phone__c' });
            String leadLookupField = getFirstExistingField(loanFieldMap, new List<String>{ 'Lead__c', 'Lead_Lookup__c' });

            if (!String.isBlank(leadLookupField) && loan.get(leadLookupField) == null) {
                loan.put(leadLookupField, leadRec.Id);
            }
            Id leadCandidateId = (Id) (leadCandidateField != null ? leadRec.get(leadCandidateField) : null);
            if (!String.isBlank(candidateField) && loan.get(candidateField) == null && leadCandidateId != null) {
                loan.put(candidateField, leadCandidateId);
            }
            String leadCourseValue = getTextValue(leadRec, leadCourseField);
            if (!String.isBlank(courseField) && loan.get(courseField) == null && !String.isBlank(leadCourseValue)) {
                loan.put(courseField, leadCourseValue);
            }
            String leadEmailValue = getTextValue(leadRec, leadEmailField);
            if (!String.isBlank(emailField) && loan.get(emailField) == null && !String.isBlank(leadEmailValue)) {
                loan.put(emailField, leadEmailValue);
            }
            String leadMobileValue = getTextValue(leadRec, leadMobileField);
            if (!String.isBlank(mobileField) && loan.get(mobileField) == null && !String.isBlank(leadMobileValue)) {
                loan.put(mobileField, leadMobileValue);
            }

            String loanFirstNameField = getFirstExistingField(loanFieldMap, new List<String>{ 'First_Name__c' });
            String leadNameValue = getTextValue(leadRec, leadNameField);
            if (!String.isBlank(loanFirstNameField) && loan.get(loanFirstNameField) == null && !String.isBlank(leadNameValue)) {
                loan.put(loanFirstNameField, leadNameValue);
            }

            Id candId = (Id) loan.get(candidateField);
            if (candId != null) {
                populateCandidateAddressOnLoan(loan, loanFieldMap, candId);
            }
        }

        applyCurrentAddressFromPermanentSingle(loan);

        // Validate candidate + course
        String candField = getFirstExistingField(loanFieldMap, new List<String>{ 'Candidate__c', 'Candidate_Id__c' });
        String crsField = getFirstExistingField(loanFieldMap, new List<String>{ 'Program_Name__c', 'Course__c' });
        if (!String.isBlank(candField) && !String.isBlank(crsField)) {
            Id candId = (Id) loan.get(candField);
            String course = (String) loan.get(crsField);
            ValidationResult vr = validateLeadCandidateCourse(candId, course);
            if (vr != null && vr.isValid == false) {
                throw new AuraHandledException(vr.message);
            }
        }

        insert loan;
        return loan.Id;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getLoanFieldApiCaseMap() {
        Map<String, String> result = new Map<String, String>();
        Map<String, Schema.SObjectField> fieldMap = Loan__c.SObjectType.getDescribe().fields.getMap();
        for (String api : fieldMap.keySet()) {
            result.put(api.toLowerCase(), api);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static LayoutResponse getLayout(Id recordTypeId) {
        System.debug('LoanQuickActionController.getLayout recordTypeId=' + recordTypeId);
        LayoutResponse response = new LayoutResponse();
        response.sections = new List<LayoutSectionDTO>();
        Schema.DescribeSObjectResult loanDescribe = Loan__c.SObjectType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = loanDescribe.fields.getMap();
        Map<String, String> fieldMapLower = new Map<String, String>();
        for (String api : fieldMap.keySet()) {
            fieldMapLower.put(api.toLowerCase(), api);
        }
        Map<Id, Schema.RecordTypeInfo> rtInfos = loanDescribe.getRecordTypeInfosById();
        String devName = null;
        if (recordTypeId != null && rtInfos.containsKey(recordTypeId)) {
            devName = rtInfos.get(recordTypeId).getDeveloperName();
        }
        System.debug('Resolved record type developerName=' + devName);

        // Fieldset naming convention:
        // Loan_<RecordTypeDeveloperName>  (e.g., Loan_AVANSE)
        // Fallback: Loan_Default
        String fieldSetName = devName != null ? ('Loan_' + devName) : null;
        Map<String, Schema.FieldSet> fieldSets = loanDescribe.fieldSets.getMap();
        Schema.FieldSet fieldSet = null;

        if (!String.isBlank(fieldSetName) && fieldSets.containsKey(fieldSetName)) {
            fieldSet = fieldSets.get(fieldSetName);
            System.debug('Using field set: ' + fieldSetName);
        } else if (fieldSets.containsKey('Loan_Default')) {
            fieldSet = fieldSets.get('Loan_Default');
            System.debug('Using fallback field set: Loan_Default');
        } else {
            System.debug('No matching field set found. fieldSetName=' + fieldSetName + ' available=' + fieldSets.keySet());
        }

        if (fieldSet == null) {
            return response;
        }

        List<Schema.FieldSetMember> fsMembers = fieldSet.getFields();
        if (fsMembers == null || fsMembers.isEmpty()) {
            System.debug('Field set has no fields: ' + fieldSet.getName());
            return response;
        }
        System.debug('Field set member count: ' + fsMembers.size());
        List<String> fsNames = new List<String>();
        for (Schema.FieldSetMember m : fsMembers) {
            fsNames.add(m.getFieldPath());
        }
        System.debug('Field set members: ' + fsNames);

        LayoutSectionDTO sectionDto = new LayoutSectionDTO();
        sectionDto.heading = 'Information';
        sectionDto.rows = new List<LayoutRowDTO>();

        Integer idx = 0;
        while (idx < fsMembers.size()) {
            LayoutRowDTO rowDto = new LayoutRowDTO();
            rowDto.cols = new List<LayoutColDTO>();

            LayoutColDTO left = new LayoutColDTO();
            left.fieldApiName = normalizeFieldApi(fsMembers[idx].getFieldPath(), fieldMapLower);
            rowDto.cols.add(left);
            idx++;

            LayoutColDTO right = new LayoutColDTO();
            if (idx < fsMembers.size()) {
                right.fieldApiName = normalizeFieldApi(fsMembers[idx].getFieldPath(), fieldMapLower);
                idx++;
            } else {
                right.fieldApiName = null;
            }
            rowDto.cols.add(right);

            sectionDto.rows.add(rowDto);
        }

        response.sections.add(sectionDto);
        System.debug('Layout sections built. rowCount=' + sectionDto.rows.size());
        System.debug('response=' + response);
        return response;
    }

    private static String getFirstExistingField(
        Map<String, Schema.SObjectField> fieldMap,
        List<String> candidates
    ) {
        if (fieldMap == null || fieldMap.isEmpty() || candidates == null || candidates.isEmpty()) {
            return null;
        }
        for (String fieldApi : candidates) {
            if (fieldMap.containsKey(fieldApi)) {
                return fieldApi;
            }
        }
        Map<String, String> lowerToActual = new Map<String, String>();
        for (String api : fieldMap.keySet()) {
            lowerToActual.put(api.toLowerCase(), api);
        }
        for (String fieldApi : candidates) {
            if (String.isBlank(fieldApi)) continue;
            String key = fieldApi.toLowerCase();
            if (lowerToActual.containsKey(key)) {
                return lowerToActual.get(key);
            }
        }
        return null;
    }

    private static String normalizeFieldApi(String fieldPath, Map<String, String> fieldMapLower) {
        if (String.isBlank(fieldPath)) return null;
        String key = fieldPath.toLowerCase();
        if (fieldMapLower != null && fieldMapLower.containsKey(key)) {
            return fieldMapLower.get(key);
        }
        return fieldPath;
    }

    private static void populateCandidateAddressPrefill(
        Map<String, Object> prefill,
        Map<String, Schema.SObjectField> loanFieldMap,
        Id candidateId
    ) {
        Schema.DescribeSObjectResult candDescribe = Lead.SObjectType.getDescribe();
        Map<String, Schema.SObjectField> candFieldMap = candDescribe.fields.getMap();

        String shipStreetField = getFirstExistingField(candFieldMap, new List<String>{ 'Shipping_Street__c', 'ShippingStreet' });
        String shipCityField = getFirstExistingField(candFieldMap, new List<String>{ 'Shipping_City__c', 'ShippingCity' });
        String shipStateField = getFirstExistingField(candFieldMap, new List<String>{ 'Shipping_State__c', 'ShippingState' });
        String shipPostalField = getFirstExistingField(candFieldMap, new List<String>{ 'Shipping_Postal_Code__c', 'ShippingPostalCode' });

        String billStreetField = getFirstExistingField(candFieldMap, new List<String>{ 'Billing_Street__c', 'BillingStreet' });
        String billCityField = getFirstExistingField(candFieldMap, new List<String>{ 'Billing_City__c', 'BillingCity' });
        String billStateField = getFirstExistingField(candFieldMap, new List<String>{ 'Billing_State__c', 'BillingState' });
        String billPostalField = getFirstExistingField(candFieldMap, new List<String>{ 'Billing_Postal_Code__c', 'BillingPostalCode' });

        List<String> fieldsToQuery = new List<String>{ 'Id' };
        addIfFieldExists(fieldsToQuery, candFieldMap, shipStreetField);
        addIfFieldExists(fieldsToQuery, candFieldMap, shipCityField);
        addIfFieldExists(fieldsToQuery, candFieldMap, shipStateField);
        addIfFieldExists(fieldsToQuery, candFieldMap, shipPostalField);
        addIfFieldExists(fieldsToQuery, candFieldMap, billStreetField);
        addIfFieldExists(fieldsToQuery, candFieldMap, billCityField);
        addIfFieldExists(fieldsToQuery, candFieldMap, billStateField);
        addIfFieldExists(fieldsToQuery, candFieldMap, billPostalField);

        if (fieldsToQuery.size() <= 1) {
            return;
        }

        String soql = 'SELECT ' + String.join(fieldsToQuery, ',') + ' FROM Lead WHERE Id = :candidateId LIMIT 1';
        Lead cand = Database.query(soql);

        String shipStreet = getTextValue(cand, shipStreetField);
        String shipCity = getTextValue(cand, shipCityField);
        String shipState = getTextValue(cand, shipStateField);
        String shipPostal = getTextValue(cand, shipPostalField);

        String billStreet = getTextValue(cand, billStreetField);
        String billCity = getTextValue(cand, billCityField);
        String billState = getTextValue(cand, billStateField);
        String billPostal = getTextValue(cand, billPostalField);

        if (String.isBlank(billStreet) && String.isBlank(billCity) && String.isBlank(billState) && String.isBlank(billPostal)) {
            billStreet = shipStreet;
            billCity = shipCity;
            billState = shipState;
            billPostal = shipPostal;
        }

        putPrefillIfExists(prefill, loanFieldMap, 'street__c', shipStreet);
        putPrefillIfExists(prefill, loanFieldMap, 'City__c', shipCity);
        putPrefillIfExists(prefill, loanFieldMap, 'State__c', shipState);
        putPrefillIfExists(prefill, loanFieldMap, 'pincode__c', shipPostal);

        putPrefillIfExists(prefill, loanFieldMap, 'permanent_street__c', billStreet);
        putPrefillIfExists(prefill, loanFieldMap, 'permanent_pincode__c', billPostal);
    }

    private static void populateCandidateAddressOnLoan(
        Loan__c loan,
        Map<String, Schema.SObjectField> loanFieldMap,
        Id candidateId
    ) {
        Map<String, Object> temp = new Map<String, Object>();
        populateCandidateAddressPrefill(temp, loanFieldMap, candidateId);
        for (String key : temp.keySet()) {
            if (loan.get(key) == null && temp.get(key) != null) {
                loan.put(key, temp.get(key));
            }
        }
    }

    private static void applyCurrentAddressFromPermanentSingle(Loan__c loan) {
        if (loan == null) return;
        if (loan.Current_Address_Same_As_Permanent__c == true) {
            loan.flat_no__c = loan.permanent_flat_no__c;
            loan.street__c = loan.permanent_street__c;
            loan.land_mark__c = loan.permanent_land_mark__c;
            loan.pincode__c = loan.permanent_pincode__c;
        }
    }

    private static void addIfFieldExists(
        List<String> listRef,
        Map<String, Schema.SObjectField> fieldMap,
        String fieldApi
    ) {
        if (String.isBlank(fieldApi)) return;
        if (fieldMap.containsKey(fieldApi) && !listRef.contains(fieldApi)) {
            listRef.add(fieldApi);
        }
    }

    private static String getTextValue(SObject record, String fieldApi) {
        if (record == null || String.isBlank(fieldApi)) return null;
        Object value = record.get(fieldApi);
        return value == null ? null : String.valueOf(value);
    }

    private static void putPrefillIfExists(
        Map<String, Object> prefill,
        Map<String, Schema.SObjectField> loanFieldMap,
        String loanFieldApi,
        String value
    ) {
        if (String.isBlank(value)) return;
        if (loanFieldMap.containsKey(loanFieldApi)) {
            prefill.put(loanFieldApi, value);
        }
    }

}
