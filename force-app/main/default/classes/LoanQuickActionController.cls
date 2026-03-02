// Author: Rohitng Singh Bisht
public with sharing class LoanQuickActionController {
    private static final String KEY_CANDIDATE = 'candidate';
    private static final String KEY_COURSE = 'course';
    private static final String KEY_EMAIL = 'email';
    private static final String KEY_MOBILE = 'mobile';
    private static final String KEY_NAME = 'name';
    private static final String KEY_LEAD_LOOKUP = 'leadLookup';
    private static final String KEY_FIRST_NAME = 'firstName';

    private static final List<String> CANDIDATE_FIELDS = new List<String>{ 'Candidate__c', 'Candidate_Id__c' };
    private static final List<String> COURSE_FIELDS = new List<String>{ 'Program_Name__c', 'Course__c' };
    private static final List<String> LEAD_LOOKUP_FIELDS = new List<String>{ 'Lead__c', 'Lead_Lookup__c' };
    private static final List<String> EMAIL_FIELDS = new List<String>{ 'Email__c' };
    private static final List<String> MOBILE_FIELDS = new List<String>{ 'Mobile__c', 'Phone__c' };
    private static final List<String> LEAD_NAME_FIELDS = new List<String>{ 'First_Name__c', 'Name' };
    private static final List<String> LOAN_FIRST_NAME_FIELDS = new List<String>{ 'First_Name__c' };
    private static final List<String> AMOUNT_FIELDS = new List<String>{ 'Amount_requested__c' };

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

        public InitData() {
            this.recordTypes = new List<RecordTypeOption>();
            this.prefillValues = new Map<String, Object>();
        }
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

        Schema.DescribeSObjectResult loanDescribe = Loan__c.SObjectType.getDescribe();
        data.recordTypes = buildRecordTypeOptions(loanDescribe);

        Map<String, Schema.SObjectField> loanFieldMap = loanDescribe.fields.getMap();
        data.candidateFieldApi = getFirstExistingField(loanFieldMap, CANDIDATE_FIELDS);
        data.courseFieldApi = getFirstExistingField(loanFieldMap, COURSE_FIELDS);
        data.leadLookupFieldApi = getFirstExistingField(loanFieldMap, LEAD_LOOKUP_FIELDS);
        data.emailFieldApi = getFirstExistingField(loanFieldMap, EMAIL_FIELDS);
        data.mobileFieldApi = getFirstExistingField(loanFieldMap, MOBILE_FIELDS);
        System.debug('Field mapping candidate=' + data.candidateFieldApi + ' course=' + data.courseFieldApi +
            ' leadLookup=' + data.leadLookupFieldApi + ' email=' + data.emailFieldApi + ' mobile=' + data.mobileFieldApi);

        Schema.DescribeSObjectResult leadDescribe = Lead__c.SObjectType.getDescribe();
        Map<String, Schema.SObjectField> leadFieldMap = leadDescribe.fields.getMap();
        Map<String, String> leadApis = resolveLeadFieldApis(leadFieldMap);

        if (leadId != null) {
            List<String> leadFieldsToQuery = new List<String>{ 'Id' };
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadApis.get(KEY_CANDIDATE));
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadApis.get(KEY_COURSE));
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadApis.get(KEY_EMAIL));
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadApis.get(KEY_MOBILE));
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadApis.get(KEY_NAME));

            String leadSoql = 'SELECT ' + String.join(leadFieldsToQuery, ',') + ' FROM Lead__c WHERE Id = :leadId LIMIT 1';
            Lead__c leadRec = Database.query(leadSoql);

            Id leadCandidateId = (Id) (leadApis.get(KEY_CANDIDATE) != null ? leadRec.get(leadApis.get(KEY_CANDIDATE)) : null);
            String leadCourseField = leadApis.get(KEY_COURSE);
            Schema.DescribeFieldResult leadCourseDescribe = leadCourseField != null && leadFieldMap.containsKey(leadCourseField)
                ? leadFieldMap.get(leadCourseField).getDescribe()
                : null;
            Object leadCourseRaw = !String.isBlank(leadCourseField) ? leadRec.get(leadCourseField) : null;
            String leadCourseValue = leadCourseRaw == null ? null : String.valueOf(leadCourseRaw);
            Id leadCourseId = leadCourseRaw instanceof Id ? (Id) leadCourseRaw : null;
            String leadCourseName = leadCourseId != null ? resolveReferenceName(leadCourseDescribe, leadCourseId) : null;
            String leadEmailValue = getTextValue(leadRec, leadApis.get(KEY_EMAIL));
            String leadMobileValue = getTextValue(leadRec, leadApis.get(KEY_MOBILE));
            String leadNameValue = getTextValue(leadRec, leadApis.get(KEY_NAME));

            if (data.candidateFieldApi != null && leadCandidateId != null) {
                data.prefillValues.put(data.candidateFieldApi, leadCandidateId);
            }
            if (leadCourseId != null || !String.isBlank(leadCourseValue)) {
                List<String> loanCourseFields = getExistingFields(loanFieldMap, COURSE_FIELDS);
                for (String loanCourseField : loanCourseFields) {
                    Schema.DescribeFieldResult loanCourseDescribe = loanFieldMap.containsKey(loanCourseField)
                        ? loanFieldMap.get(loanCourseField).getDescribe()
                        : null;
                    Boolean loanCourseIsRef = loanCourseDescribe != null && loanCourseDescribe.getType() == Schema.DisplayType.Reference;

                    if (loanCourseIsRef) {
                        if (leadCourseId != null) {
                            data.prefillValues.put(loanCourseField, leadCourseId);
                        }
                    } else {
                        String courseText = leadCourseId != null ? leadCourseName : leadCourseValue;
                        if (!String.isBlank(courseText)) {
                            data.prefillValues.put(loanCourseField, courseText);
                        }
                    }
                }
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

            String loanFirstNameField = getFirstExistingField(loanFieldMap, LOAN_FIRST_NAME_FIELDS);
            if (!String.isBlank(loanFirstNameField) && !String.isBlank(leadNameValue)) {
                data.prefillValues.put(loanFirstNameField, leadNameValue);
            }

            Id candidateId = leadCandidateId;
            if (candidateId != null) {
                populateCandidateAddressPrefill(data.prefillValues, loanFieldMap, candidateId);
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
        Map<String, String> loanLowerMap = buildLowercaseApiMap(loanFieldMap.keySet());

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
            loan.put(api, coerceFieldValue(fields.get(key), loanFieldMap.get(api)));
        }

        if (leadId != null) {
            Schema.DescribeSObjectResult leadDescribe = Lead__c.SObjectType.getDescribe();
            Map<String, Schema.SObjectField> leadFieldMap = leadDescribe.fields.getMap();
            Map<String, String> leadApis = resolveLeadFieldApis(leadFieldMap);

            List<String> leadFieldsToQuery = new List<String>{ 'Id' };
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadApis.get(KEY_CANDIDATE));
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadApis.get(KEY_COURSE));
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadApis.get(KEY_EMAIL));
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadApis.get(KEY_MOBILE));
            addIfFieldExists(leadFieldsToQuery, leadFieldMap, leadApis.get(KEY_NAME));

            String leadSoql = 'SELECT ' + String.join(leadFieldsToQuery, ',') + ' FROM Lead__c WHERE Id = :leadId LIMIT 1';
            Lead__c leadRec = Database.query(leadSoql);

            Map<String, String> loanApis = resolveLoanFieldApis(loanFieldMap);
            String leadLookupField = loanApis.get(KEY_LEAD_LOOKUP);
            String candidateField = loanApis.get(KEY_CANDIDATE);
            String courseField = loanApis.get(KEY_COURSE);
            String emailField = loanApis.get(KEY_EMAIL);
            String mobileField = loanApis.get(KEY_MOBILE);
            String loanFirstNameField = loanApis.get(KEY_FIRST_NAME);

            if (!String.isBlank(leadLookupField) && loan.get(leadLookupField) == null) {
                loan.put(leadLookupField, leadRec.Id);
            }

            Id leadCandidateId = (Id) (leadApis.get(KEY_CANDIDATE) != null ? leadRec.get(leadApis.get(KEY_CANDIDATE)) : null);
            if (!String.isBlank(candidateField) && loan.get(candidateField) == null && leadCandidateId != null) {
                loan.put(candidateField, leadCandidateId);
            }

            String leadCourseValue = getTextValue(leadRec, leadApis.get(KEY_COURSE));
            if (!String.isBlank(courseField) && loan.get(courseField) == null && !String.isBlank(leadCourseValue)) {
                loan.put(courseField, leadCourseValue);
            }

            String leadEmailValue = getTextValue(leadRec, leadApis.get(KEY_EMAIL));
            if (!String.isBlank(emailField) && loan.get(emailField) == null && !String.isBlank(leadEmailValue)) {
                loan.put(emailField, leadEmailValue);
            }

            String leadMobileValue = getTextValue(leadRec, leadApis.get(KEY_MOBILE));
            if (!String.isBlank(mobileField) && loan.get(mobileField) == null && !String.isBlank(leadMobileValue)) {
                loan.put(mobileField, leadMobileValue);
            }

            String leadNameValue = getTextValue(leadRec, leadApis.get(KEY_NAME));
            if (!String.isBlank(loanFirstNameField) && loan.get(loanFirstNameField) == null && !String.isBlank(leadNameValue)) {
                loan.put(loanFirstNameField, leadNameValue);
            }

            Id candId = (Id) loan.get(candidateField);
            if (candId != null) {
                populateCandidateAddressOnLoan(loan, loanFieldMap, candId);
            }

            if (leadId != null && recordTypeId != null) {
                List<Loan__c> existingLoans = [
                    SELECT Id, Loan_Status__c
                    FROM Loan__c
                    WHERE Lead__c = :leadId
                      AND RecordTypeId = :recordTypeId
                      AND Loan_Status__c IN ('In Progress', 'Approved')
                    LIMIT 1
                ];

                if (!existingLoans.isEmpty()) {
                    throw new AuraHandledException(
                        'A Loan is already In Progress or Approved for this Lead and Loan Provider.'
                    );
                }
            }
        }

        applyCurrentAddressFromPermanentSingle(loan);

        // Validate candidate + course
        String candField = getFirstExistingField(loanFieldMap, CANDIDATE_FIELDS);
        String crsField = getFirstExistingField(loanFieldMap, COURSE_FIELDS);
        if (!String.isBlank(candField) && !String.isBlank(crsField)) {
            Id candIdForValidation = (Id) loan.get(candField);
            String course = (String) loan.get(crsField);
            ValidationResult vr = validateLeadCandidateCourse(candIdForValidation, course);
            if (vr != null && vr.isValid == false) {
                throw new AuraHandledException(vr.message);
            }
        }

        // ================= PROGRAM AMOUNT VALIDATION =================
        String programField = getFirstExistingField(loanFieldMap, COURSE_FIELDS);
        String amountField = getFirstExistingField(loanFieldMap, AMOUNT_FIELDS);

        if (!String.isBlank(programField) && !String.isBlank(amountField)) {
            String program = (String) loan.get(programField);
            Decimal amount = (Decimal) loan.get(amountField);

            if (!String.isBlank(program) && amount != null) {
                // CPA / CMA -> Max 79,000
                if ((program == 'CPA' || program == 'CMA') && amount > 79000) {
                    throw new AuraHandledException(
                        'Requested amount exceeds the maximum limit for the selected Program.\n' +
                        'CPA/CMA: Max 79,000'
                    );
                }

                // CAIRA -> Max 40,000
                if (program == 'CAIRA' && amount > 40000) {
                    throw new AuraHandledException(
                        'Requested amount exceeds the maximum limit for the selected Program.\n' +
                        'CAIRA: Max 40,000'
                    );
                }
            }
        }

        // ================= AKSHAR VALIDATION =================
        if (recordTypeId != null) {
            Schema.RecordTypeInfo rtInfo = Loan__c.SObjectType
                .getDescribe()
                .getRecordTypeInfosById()
                .get(recordTypeId);

            if (rtInfo != null && rtInfo.getDeveloperName() == 'AKSHAR') {
                // PAN Validation
                String pan = (String) loan.get('PAN_Number__c');
                if (String.isBlank(pan)) {
                    throw new AuraHandledException('PAN Number is required for AKSHAR.');
                }

                // PAN Format: 5 letters + 4 digits + 1 letter
                Pattern panPattern = Pattern.compile('^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
                if (!panPattern.matcher(pan).matches()) {
                    throw new AuraHandledException('Invalid PAN format. Example: ABCDE1234F');
                }

                // DOB Validation (Minimum 18 years)
                Date dob = (Date) loan.get('Date_of_Birth__c');
                if (dob == null) {
                    throw new AuraHandledException('Date of Birth is required for AKSHAR.');
                }

                Integer age = Date.today().year() - dob.year();
                if (Date.today().addYears(-age) < dob) {
                    age--;
                }

                if (age < 18) {
                    throw new AuraHandledException('Applicant must be at least 18 years old for AKSHAR.');
                }
            }
        }

        // Call vendor API before insert. Throw if it fails.
        Callout_CreationApiService.callAndPopulate(loan);

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

    private static List<RecordTypeOption> buildRecordTypeOptions(Schema.DescribeSObjectResult loanDescribe) {
        List<RecordTypeOption> options = new List<RecordTypeOption>();
        Map<Id, Schema.RecordTypeInfo> rtInfos = loanDescribe.getRecordTypeInfosById();
        System.debug('RecordType count=' + rtInfos.size());
        for (Id rtId : rtInfos.keySet()) {
            Schema.RecordTypeInfo info = rtInfos.get(rtId);
            if (info != null && info.isAvailable() && !info.isMaster()) {
                System.debug('RecordType available: ' + info.getDeveloperName() + ' (' + info.getName() + ')');
                options.add(new RecordTypeOption(info.getName(), String.valueOf(rtId), info.getDeveloperName()));
            }
        }
        return options;
    }

    private static Map<String, String> buildLowercaseApiMap(Set<String> apis) {
        Map<String, String> lowerMap = new Map<String, String>();
        for (String api : apis) {
            lowerMap.put(api.toLowerCase(), api);
        }
        return lowerMap;
    }

    private static Map<String, String> resolveLeadFieldApis(Map<String, Schema.SObjectField> fieldMap) {
        Map<String, String> result = new Map<String, String>();
        result.put(KEY_CANDIDATE, getFirstExistingField(fieldMap, CANDIDATE_FIELDS));
        result.put(KEY_COURSE, getFirstExistingField(fieldMap, COURSE_FIELDS));
        result.put(KEY_EMAIL, getFirstExistingField(fieldMap, EMAIL_FIELDS));
        result.put(KEY_MOBILE, getFirstExistingField(fieldMap, MOBILE_FIELDS));
        result.put(KEY_NAME, getFirstExistingField(fieldMap, LEAD_NAME_FIELDS));
        return result;
    }

    private static Map<String, String> resolveLoanFieldApis(Map<String, Schema.SObjectField> fieldMap) {
        Map<String, String> result = new Map<String, String>();
        result.put(KEY_CANDIDATE, getFirstExistingField(fieldMap, CANDIDATE_FIELDS));
        result.put(KEY_COURSE, getFirstExistingField(fieldMap, COURSE_FIELDS));
        result.put(KEY_EMAIL, getFirstExistingField(fieldMap, EMAIL_FIELDS));
        result.put(KEY_MOBILE, getFirstExistingField(fieldMap, MOBILE_FIELDS));
        result.put(KEY_LEAD_LOOKUP, getFirstExistingField(fieldMap, LEAD_LOOKUP_FIELDS));
        result.put(KEY_FIRST_NAME, getFirstExistingField(fieldMap, LOAN_FIRST_NAME_FIELDS));
        return result;
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

    private static List<String> getExistingFields(
        Map<String, Schema.SObjectField> fieldMap,
        List<String> candidates
    ) {
        List<String> result = new List<String>();
        if (fieldMap == null || fieldMap.isEmpty() || candidates == null || candidates.isEmpty()) {
            return result;
        }
        Map<String, String> lowerToActual = new Map<String, String>();
        for (String api : fieldMap.keySet()) {
            lowerToActual.put(api.toLowerCase(), api);
        }
        for (String fieldApi : candidates) {
            if (String.isBlank(fieldApi)) continue;
            String key = fieldApi.toLowerCase();
            if (lowerToActual.containsKey(key)) {
                result.add(lowerToActual.get(key));
            }
        }
        return result;
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

    private static String resolveReferenceName(Schema.DescribeFieldResult fieldDescribe, Id recordId) {
        if (fieldDescribe == null || recordId == null) return null;
        if (fieldDescribe.getType() != Schema.DisplayType.Reference) return null;
        List<Schema.SObjectType> refTypes = fieldDescribe.getReferenceTo();
        if (refTypes == null || refTypes.isEmpty()) return null;
        Schema.DescribeSObjectResult refDescribe = refTypes[0].getDescribe();
        Map<String, Schema.SObjectField> refFieldMap = refDescribe.fields.getMap();
        String nameField = null;
        if (refFieldMap != null) {
            if (refFieldMap.containsKey('Name')) {
                nameField = 'Name';
            } else {
                for (String api : refFieldMap.keySet()) {
                    Schema.DescribeFieldResult d = refFieldMap.get(api).getDescribe();
                    if (d != null && d.isNameField()) {
                        nameField = api;
                        break;
                    }
                }
            }
        }
        if (String.isBlank(nameField)) return null;
        String soql = 'SELECT ' + nameField + ' FROM ' + refDescribe.getName() + ' WHERE Id = :recordId LIMIT 1';
        SObject refRec = Database.query(soql);
        Object nameVal = refRec.get(nameField);
        return nameVal == null ? null : String.valueOf(nameVal);
    }

    private static Object coerceFieldValue(Object rawValue, Schema.SObjectField fieldRef) {
        if (rawValue == null || fieldRef == null) return rawValue;
        Schema.DescribeFieldResult d = fieldRef.getDescribe();
        Schema.DisplayType t = d.getType();

        if (rawValue instanceof String) {
            String s = (String) rawValue;
            if (String.isBlank(s)) return null;

            try {
                if (t == Schema.DisplayType.Currency
                    || t == Schema.DisplayType.Double
                    || t == Schema.DisplayType.Percent) {
                    return Decimal.valueOf(s);
                }
                if (t == Schema.DisplayType.Integer) {
                    return Integer.valueOf(s);
                }
                if (t == Schema.DisplayType.Boolean) {
                    return s.equalsIgnoreCase('true');
                }
                if (t == Schema.DisplayType.Date) {
                    return Date.valueOf(s);
                }
                if (t == Schema.DisplayType.DateTime) {
                    return DateTime.valueOf(s);
                }
            } catch (Exception e) {
                // Keep raw value if parsing fails to avoid hard error here.
                return rawValue;
            }
        }
        return rawValue;
    }
}