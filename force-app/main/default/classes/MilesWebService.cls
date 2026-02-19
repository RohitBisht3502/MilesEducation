/*
Author             : ROHIT SINGH BISHT
Description        :
Last Modified      : ROHIT SINGH BISHT
Last Modified Date : 1 DEC 2025
*/
@RestResource(urlMapping='/milessite/*')
global without sharing class MilesWebService {

    private static final String EXPECTED_SECURITY_CODE = 'MY_SECURE_CODE_123';

    private enum EmailDecision {
        SAME_LEAD,              // Email exists with SAME Lead
        DIFFERENT_LEAD,         // Email exists with DIFFERENT Lead
        CREATED_AND_ASSOCIATED, // Email not exist -> created & associated
        ASSOCIATED_TO_LEAD      // Email existed but unlinked -> now linked (safe case)
    }

    @HttpPost
    global static ApiResponse doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            /* ------------ SECURITY CHECK ------------- */
            String securityCode = req.headers.get('securityCode');
            if (String.isBlank(securityCode)) {
                IntegrationLogUtil.insertLogs(new List<Integration_Log__c>{
                    IntegrationLogUtil.buildLog('Enquiry', null, null, 'Missing required header: securityCode', 'FAILED', null)
                });
                res.statusCode = 400;
                return new ApiResponse(false, 'Missing required header: securityCode', null);
            }
            if (securityCode != EXPECTED_SECURITY_CODE) {
                IntegrationLogUtil.insertLogs(new List<Integration_Log__c>{
                    IntegrationLogUtil.buildLog('Enquiry', null, null, 'Unauthorized: Invalid security code. Provided=' + securityCode, 'FAILED', null)
                });                
                res.statusCode = 401;
                return new ApiResponse(false, 'Unauthorized: Invalid security code', null);
            }

            /* ------------ BODY CHECK ------------- */
            String requestBody = (req.requestBody != null) ? req.requestBody.toString() : '';
            if (String.isBlank(requestBody)) {
                IntegrationLogUtil.insertLogs(new List<Integration_Log__c>{
                    IntegrationLogUtil.buildLog('Enquiry', null, null, 'Request body is empty', 'FAILED', null)
                });                
                res.statusCode = 400;
                return new ApiResponse(false, 'Request body is empty', null);
            }

            System.debug('MilesWebService RequestBody => ' + requestBody);

            IntegrationLogUtil.insertLogs(new List<Integration_Log__c>{
                IntegrationLogUtil.buildLog('Enquiry', requestBody, null, null, 'SUCCESS', null)
            });

            EnquiryWrapper inputData = (EnquiryWrapper) JSON.deserialize(requestBody, EnquiryWrapper.class);

            // ================= DUMMY DEFAULT VALUES =================
            if (String.isBlank(inputData.city)) inputData.city = 'Mumbai';
            if (String.isBlank(inputData.course)) inputData.course = 'CMA';
            if (inputData.city_id == null) inputData.city_id = 8;
            if (inputData.smsAllow == null) inputData.smsAllow = 1;
            if (String.isBlank(inputData.coming_from)) inputData.coming_from = 'Facebook';
            if (inputData.whatsappAllow == null) inputData.whatsappAllow = 1;
            if (inputData.whatsapp_opt_in == null) inputData.whatsapp_opt_in = true;
            if (String.isBlank(inputData.highestEducation)) inputData.highestEducation = 'Graduate';
            if (String.isBlank(inputData.country_of_residence)) inputData.country_of_residence = 'India';
            if (inputData.register_for_webinar == null) inputData.register_for_webinar = false;
            if (String.isBlank(inputData.interested_webinar_id)) inputData.interested_webinar_id = 'ROMAN';
            // ========================================================

            if (String.isBlank(inputData.first_name) || String.isBlank(inputData.phone)) {
                IntegrationLogUtil.insertLogs(new List<Integration_Log__c>{
                    IntegrationLogUtil.buildLog('Enquiry', requestBody, null, 'Missing required fields: first_name or phone', 'FAILED', null)
                });                
                res.statusCode = 400;
                return new ApiResponse(false, 'Missing required fields: first_name or phone', null);
            }

            Boolean whatsappAllow = (inputData.whatsappAllow != null && inputData.whatsappAllow == 1);

            /* ------------ CREATE ENQUIRY ------------- */
            Enquiry__c enquiry = new Enquiry__c(
                Name                     = inputData.first_name,
                First_Name__c            = inputData.first_name,
                Phone_Number__c          = inputData.phone,
                Email__c                 = inputData.email,
                City__c                  = inputData.city,
                Course__c                = inputData.course,
                City_Id__c               = inputData.city_id,
                SMS_Allow__c             = (inputData.smsAllow == 1),
                Coming_From__c           = inputData.coming_from,
                WhatsApp_Allow__c        = whatsappAllow,
                WhatsApp_Opt_In__c       = inputData.whatsapp_opt_in,
                Highest_Education__c     = inputData.highestEducation,
                Country_of_Residence__c  = inputData.country_of_residence,
                Register_for_Webinar__c  = inputData.register_for_webinar,
                Interested_Webinar_ID__c = inputData.interested_webinar_id,
                Campaign_Name__c         = inputData.campaign_tk, 
                Stage__c                 = 'Untracked' // Default value Untracked.
            );
            insert enquiry;

            // Step 1: Check Phone number exist or not (Phone_Number__c)
            Phone_Number__c phoneExisting;
            Id studentAccountId;
            Id candidateIdFromPhone;

            // checking all scnerios number staring from +91,0 etc
            Set<String> phoneVariants = Utility.buildPhoneVariants(inputData.phone);
            
            List<Phone_Number__c> phoneExistingList = [SELECT Id, Phone__c, Candidate__c, Student__c FROM Phone_Number__c WHERE Phone__c IN :phoneVariants LIMIT 1];
            if (!phoneExistingList.isEmpty()) {
                phoneExisting       = phoneExistingList[0];
                studentAccountId    = phoneExisting.Student__c;
                candidateIdFromPhone = phoneExisting.Candidate__c;
            }

            Boolean phoneExists = (phoneExisting != null);
            // check Account exist or not 
            Boolean isConvertedStudent = (studentAccountId != null);
            // check candidate exist or not 
            Lead candidate;
            if (!isConvertedStudent && candidateIdFromPhone != null) {
                List<Lead> candById = [SELECT Id, OwnerId, Phone, Email FROM Lead WHERE Id = :candidateIdFromPhone LIMIT 1];
                if (!candById.isEmpty()) candidate = candById[0];
            }

            // Decide: Candidate should be created:
            Boolean shouldCreateCandidate = (!isConvertedStudent && candidate == null);

            // update enquiry 
            Id enquiryCandidateId;
            Id enquiryStudentId;
            Id enquiryLeadId;

            enquiryStudentId = (studentAccountId != null ? studentAccountId : null);

            Lead__c leadToReturn;

            Id leadRecordTypeId = getLeadRecordTypeId(inputData.course);
            String leadDefaultStage = getDefaultStageForCourse(inputData.course);

            /* =====================================================
               CASE 0: PHONE NOT EXIST 
               Not Exist -> Create Candidate -> Create Lead -> Create Phone Number -> Email Associations
               ===================================================== */
            if (!phoneExists) {

                // Create Candidate (Lead)
                candidate = new Lead(
                    LastName                 = inputData.first_name,
                    Company                  = 'Miles Education',
                    Phone                    = inputData.phone,
                    Email                    = inputData.email,
                    Course__c                = inputData.course,
                    Coming_From__c           = inputData.coming_from,
                    Register_for_Webinar__c  = inputData.register_for_webinar,
                    Interested_Webinar_ID__c = inputData.interested_webinar_id
                );
                insert candidate;

                // Create Lead__c
                Lead__c newLead = new Lead__c(
                    Name                     = inputData.first_name,
                    Phone__c                 = inputData.phone,
                    Email__c                 = inputData.email,
                    Stage__c                 = leadDefaultStage,
                    Course__c                = inputData.course,
                    Source__c                = inputData.coming_from,
                    Register_for_Webinar__c  = inputData.register_for_webinar,
                    Interested_Webinar_ID__c = inputData.interested_webinar_id,
                    Candidate__c             = candidate.Id,
                    RecordTypeId             = leadRecordTypeId
                );
                insert newLead;

                // Create Phone_Number__c (tag phone)
                Phone_Number__c phoneRec = new Phone_Number__c(
                    Name         = inputData.phone,
                    Phone__c     = inputData.phone,
                    Candidate__c = candidate.Id,
                    Is_Primary__c = true
                );
                insert phoneRec;

                enquiryCandidateId = candidate.Id;
                enquiryLeadId      = newLead.Id;
                leadToReturn       = newLead;

                // Email Associations
                EmailDecision ed = handleEmailAssociation(inputData.email, candidate.Id, enquiry.Id, studentAccountId);

            } else {

                /* =====================================================
                   CASE 1: PHONE EXIST (Diagram Right Branch)
                   -> Check Account exist or not (Student__c on phone)
                   ===================================================== */

                // If account NOT exist => check candidate exist; else skip candidate check
                if (!isConvertedStudent && shouldCreateCandidate) {
                    // Candidate Not Exist -> Create Candidate
                    candidate = new Lead(
                        LastName                 = inputData.first_name,
                        Company                  = 'Miles Education',
                        Phone                    = inputData.phone,
                        Email                    = inputData.email,
                        Course__c                = inputData.course,
                        Coming_From__c           = inputData.coming_from,
                        Register_for_Webinar__c  = inputData.register_for_webinar,
                        Interested_Webinar_ID__c = inputData.interested_webinar_id
                    );
                    insert candidate;
                }

                // For enquiry linking
                enquiryCandidateId = (candidate != null ? candidate.Id : null);
                Id candidateIdForLead = (enquiryCandidateId != null ? enquiryCandidateId : candidateIdFromPhone);

                /* =====================================================
                   Next: Check Lead exist with same course
                   - If converted student: search by Student__c + Course
                   - Else: search by Candidate__c + Course
                   ===================================================== */
                Lead__c existingLeadC;
                if (isConvertedStudent && studentAccountId != null) {
                    List<Lead__c> leadCs = [
                        SELECT Id, Stage__c, Is_ReEnquiry__c, OwnerId,Candidate__c
                        FROM Lead__c
                        WHERE Student__c = :studentAccountId AND Course__c = :inputData.course
                        LIMIT 1
                    ];
                    if (!leadCs.isEmpty()) existingLeadC = leadCs[0];
                } else if (candidate != null && candidate.Id != null) {
                    List<Lead__c> leadCs = [
                        SELECT Id, Stage__c, Is_ReEnquiry__c, OwnerId,Candidate__c
                        FROM Lead__c
                        WHERE Candidate__c = :candidate.Id AND Course__c = :inputData.course
                        LIMIT 1
                    ];
                    if (!leadCs.isEmpty()) existingLeadC = leadCs[0];
                }

                /* ------------------- LEAD EXISTS (same course) ------------------- */
                if (existingLeadC != null) {

                    enquiryLeadId = existingLeadC.Id;
                    leadToReturn  = existingLeadC;
                    if (existingLeadC.Candidate__c == null && candidateIdForLead != null) {
                        existingLeadC.Candidate__c = candidateIdForLead;
                        update existingLeadC;
                    }

                    // Email Associations
                    EmailDecision ed = handleEmailAssociation(inputData.email, enquiryCandidateId, enquiry.Id, studentAccountId);

                    // If Email is same/unlinked/created -> mark re-enquiry (as in your current logic)
                    if (ed == EmailDecision.SAME_LEAD ||
                        ed == EmailDecision.CREATED_AND_ASSOCIATED ||
                        ed == EmailDecision.ASSOCIATED_TO_LEAD) {

                        markReEnquiry(existingLeadC, enquiry);
                    } else if (ed == EmailDecision.DIFFERENT_LEAD) {
                        System.debug('Email is with different Lead. Not associating. No re-enquiry marking as per flow.');
                    }

                } else {

                    /* ------------------- LEAD NOT EXIST (same course) ------------------- */
                    // Create lead with that course + tag the phone number + email associations

                    Lead__c newLead2 = new Lead__c(
                        Name                     = inputData.first_name,
                        Phone__c                 = inputData.phone,
                        Email__c                 = inputData.email,
                        Stage__c                 = leadDefaultStage,
                        Course__c                = inputData.course,
                        Source__c                = inputData.coming_from,
                        Register_for_Webinar__c  = inputData.register_for_webinar,
                        Interested_Webinar_ID__c = inputData.interested_webinar_id,
                        Candidate__c             = (candidateIdForLead != null ? candidateIdForLead : null),
                        RecordTypeId             = leadRecordTypeId,
                        Student__c               = (studentAccountId != null ? studentAccountId : null)
                    );
                    insert newLead2;

                    // Tag the phone number (existing phone record)
                    if (phoneExisting != null) {
                        Boolean phoneChanged = false;
                        if (phoneExisting.Candidate__c == null && enquiryCandidateId != null) {
                            phoneExisting.Candidate__c = enquiryCandidateId;
                            phoneChanged = true;
                        }
                        if (phoneChanged) update phoneExisting;
                    }

                    enquiryLeadId = newLead2.Id;
                    leadToReturn  = newLead2;

                    // Email Associations
                    EmailDecision ed = handleEmailAssociation(inputData.email, enquiryCandidateId, enquiry.Id, studentAccountId);

                    if (ed == EmailDecision.DIFFERENT_LEAD) {
                        System.debug('Email exists with different Lead. Not associating.');
                    }
                }
            }

            enquiry.Candidate__c = enquiryCandidateId;
            enquiry.Student__c   = (studentAccountId != null ? studentAccountId : null);
            enquiry.Lead__c      = enquiryLeadId;
            update enquiry;

            /* ------------------- CREATE FOLLOW-UP TASK ------------------- */
            String taskSubject = 'Follow Up Call';
            // Task t = MilesExistingEnquiryWebService.createFollowUpTask(enquiry, taskSubject);

            res.statusCode = 201;
            return new ApiResponse(true, 'Enquiry processed as per flow.', leadToReturn != null ? leadToReturn.Id : null);

        } catch (Exception ex) {
            System.debug('MilesWebService Error => ' + ex.getMessage() + ' :: ' + ex.getStackTraceString());
            RestContext.response.statusCode = 500;

            IntegrationLogUtil.insertLogs(new List<Integration_Log__c>{
                IntegrationLogUtil.buildLog('Enquiry', null, null, 'Error: ' + ex.getMessage(), 'FAILED', null)
            });

            return new ApiResponse(false, 'Error: ' + ex.getMessage(), null);
        }
    }

    private static EmailDecision handleEmailAssociation(String email, Id candidateId, Id enquiryId, Id studentAccountId) {

        if (String.isBlank(email)) {
            System.debug('Email association skipped: blank email');
            return null;
        }

        List<Email__c> emailList = [SELECT Id, Candidate__c FROM Email__c WHERE Email__c = :email LIMIT 1 ];

        // Email exists
        if (!emailList.isEmpty()) {
            Email__c existingEmail = emailList[0];

            // Email exists -> only associate to candidate (do not touch Lead__c)
            if (existingEmail.Candidate__c == null) existingEmail.Candidate__c = candidateId;
            // if (existingEmail.Enquiry__c == null)   existingEmail.Enquiry__c   = enquiryId;
            update existingEmail;

            System.debug('Email__c existed. Candidate associated if missing.');
            return EmailDecision.ASSOCIATED_TO_LEAD;
        }

        // Email Not Exist in SF -> Create email and associate
        Email__c newEmail = new Email__c(
            Email__c         = email,
            Candidate__c     = candidateId,
            Student__c       = (studentAccountId != null ? studentAccountId : null),
            Is_Primary__c    = true
        );
        insert newEmail;

        System.debug('Email__c created and associated.');
        return EmailDecision.CREATED_AND_ASSOCIATED;
    }

    /* =====================================================
        RE-ENQUIRY MARKING
        ===================================================== */
    private static void markReEnquiry(Lead__c leadRec, Enquiry__c enquiryRec) {
        try {
            if (leadRec != null) {
                if (leadRec.Stage__c == 'M1' || leadRec.Stage__c == 'M2' || leadRec.Stage__c == 'M3') {
                    leadRec.Stage__c = 'M3+';
                } else if (leadRec.Stage__c == 'M4' || leadRec.Stage__c == 'M4-') {
                    leadRec.Stage__c = 'M5';
                }
                leadRec.Is_ReEnquiry__c = true;
                update leadRec;
            }

            if (enquiryRec != null) {
                // safe set (in case field is not present)
                enquiryRec.put('Is_ReEnquiry__c', true);
                update enquiryRec;
            }

            System.debug('Marked Lead__c and Enquiry__c as ReEnquiry.');

        } catch (Exception e) {
            System.debug('ReEnquiry marking failed: ' + e.getMessage());
        }
    }

    private static Id getLeadRecordTypeId(String course) {
        if (String.isBlank(course)) return null;
        String courseKey = course.trim().toUpperCase();
        String rtName;
        if (courseKey.contains('US PATHWAY')) {
            rtName = 'US Pathway';
        } else if (courseKey.contains('CPA')) {
            rtName = 'CPA';
        } else if (courseKey.contains('CMA')) {
            rtName = 'CMA';
        } else if (courseKey.contains('CAIRA')) {
            rtName = 'CAIRA';
        } else if (courseKey.contains('MCOM')) {
            rtName = 'MCOM';
        } else {
            return null;
        }

        Map<String, Schema.RecordTypeInfo> rtByName = Schema.SObjectType.Lead__c.getRecordTypeInfosByName();
        if (rtByName != null && rtByName.containsKey(rtName)) {
            return rtByName.get(rtName).getRecordTypeId();
        }
        return null;
    }

    private static String getDefaultStageForCourse(String course) {
        if (String.isBlank(course)) return 'M3';
        String courseKey = course.trim().toUpperCase();
        if (courseKey.contains('US PATHWAY')) return 'U3';
        if (courseKey.contains('MCOM')) return 'B3';
        if (courseKey.contains('CPA') || courseKey.contains('CMA') || courseKey.contains('CAIRA')) return 'M3';
        return 'M3';
    }

    /* ------------ WRAPPERS ------------- */
    global class EnquiryWrapper {
        public String city;
        public String email;
        public String phone;
        public String course;
        public Integer city_id;
        public Integer smsAllow;
        public String first_name;
        public String coming_from;
        public Integer whatsappAllow;
        public Boolean whatsapp_opt_in;
        public String highestEducation;
        public String country_of_residence;
        public Boolean register_for_webinar;
        public String interested_webinar_id;
        public String campaign_tk;
        public String stage;
    }

    global class ApiResponse {
        public Boolean success;
        public String message;
        public String recordId;
        public ApiResponse(Boolean success, String message, String recordId) {
            this.success  = success;
            this.message  = message;
            this.recordId = recordId;
        }
    }
}