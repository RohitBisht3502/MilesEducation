/*
    Author             : ROHIT SINGH BISHT
    Description        : 
    Last Modified      : ROHIT SINGH BISHT
    Last Modified Date : 1 DEC 2025
*/
@RestResource(urlMapping='/milessite/*')
global without sharing class MilesWebService {

    private static final String EXPECTED_SECURITY_CODE = 'MY_SECURE_CODE_123';

    // Email association outcomes
    private enum EmailDecision {
        SAME_LEAD,          // Email exists with SAME Lead
        DIFFERENT_LEAD,     // Email exists with DIFFERENT Lead
        CREATED_AND_ASSOCIATED, // Email not exist -> created & associated
        ASSOCIATED_TO_LEAD  // Email existed but unlinked -> now linked (safe case)
    }

    @HttpPost
    global static String doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            /* ------------ SECURITY CHECK ------------- */
            String securityCode = req.headers.get('securityCode');
            if (String.isBlank(securityCode)) {
                res.statusCode = 400;
                return 'Missing required header: securityCode';
            }
            if (securityCode != EXPECTED_SECURITY_CODE) {
                res.statusCode = 401;
                return 'Unauthorized: Invalid security code';
            }

            /* ------------ BODY CHECK ------------- */
            String requestBody = (req.requestBody != null) ? req.requestBody.toString() : '';
            if (String.isBlank(requestBody)) {
                res.statusCode = 400;
                return 'Request body is empty';
            }

            System.debug('MilesWebService RequestBody => ' + requestBody);

            IntegrationLogUtil.insertLogs(new List<Integration_Log__c>{
                IntegrationLogUtil.buildLog('Enquiry', requestBody, null, null, 'SUCCESS', null)
            });

            EnquiryWrapper inputData = (EnquiryWrapper) JSON.deserialize(requestBody, EnquiryWrapper.class);

            if (String.isBlank(inputData.first_name) || String.isBlank(inputData.phone)) {
                res.statusCode = 400;
                return 'Missing required fields: first_name or phone';
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
                Stage__c                 = 'Tracked'
            );
            insert enquiry;

            /* =====================================================
                     FLOW IMPLEMENTATION (Candidate = Lead)
               ===================================================== */

            /* 1) CHECK CANDIDATE (Lead) BY PHONE (Priority) */
            Lead candidate;
            List<Lead> candidateList = [SELECT Id,OwnerId, Phone, Email FROM Lead WHERE Phone = :inputData.phone LIMIT 1];
            if (!candidateList.isEmpty()) {
                candidate = candidateList[0];
            }

            Lead__c leadToReturn;

            /* =====================================================
               CASE A: CANDIDATE NOT EXIST
               Diagram: Not Exist -> Create Phone Number -> Create Candidate -> Create Lead (course/phone)
               ===================================================== */
            if (candidate == null) {

                // (A1) Create Phone_Number__c first (first create phone record)
                Phone_Number__c phoneRec = new Phone_Number__c(
                    Name     = inputData.phone,
                    Phone__c = inputData.phone
                );
                insert phoneRec;

                // (A2) Create Candidate (Lead)
                candidate = new Lead(
                    LastName                 = inputData.first_name,
                    Company                  = 'Test Company',
                    Phone                    = inputData.phone,
                    Email                    = inputData.email,
                    Coming_From__c           = inputData.coming_from,
                    Register_for_Webinar__c  = inputData.register_for_webinar,
                    Interested_Webinar_ID__c = inputData.interested_webinar_id
                );
                insert candidate;

                // tag phone record with candidate
                phoneRec.Candidate__c = candidate.Id;
                update phoneRec;

                // (A3) Create Lead__c with course/phone
                Lead__c newLead = new Lead__c(
                    Name                     = inputData.first_name,
                    Phone__c                 = inputData.phone,
                    Email__c                 = inputData.email,
                    Stage__c                 = 'M3',
                    Course__c                = inputData.course,
                    Source__c                = inputData.coming_from,
                    Register_for_Webinar__c  = inputData.register_for_webinar,
                    Interested_Webinar_ID__c = inputData.interested_webinar_id,
                    Candidate__c             = candidate.Id
                );
                insert newLead;

                // tag phone record with lead
                phoneRec.Lead__c = newLead.Id;
                update phoneRec;

                // link enquiry
                enquiry.Candidate__c = candidate.Id;
                enquiry.Lead__c      = newLead.Id;
                update enquiry;

                leadToReturn = newLead;

                // Email association (diagram: check email associated)
                EmailDecision ed = handleEmailAssociation(inputData.email, leadToReturn.Id, candidate.Id, enquiry.Id);

            } else {

                /* =====================================================
                   CASE B: CANDIDATE EXISTS
                   Diagram: Candidate Exists -> Check Lead with Phone + Source
                   ===================================================== */

                enquiry.Candidate__c = candidate.Id;
                update enquiry;

                // 2) Check Lead__c with Phone + Source (as per NEW diagram)
                Lead__c existingLeadC;
                List<Lead__c> leadCs = [SELECT Id, Stage__c, Is_ReEnquiry__c,OwnerId FROM Lead__c WHERE Phone__c = :inputData.phone AND Source__c  = :inputData.coming_from LIMIT 1 ];
                if (!leadCs.isEmpty()) existingLeadC = leadCs[0];

                /* ------------------- B1: LEAD EXISTS (Phone + Source) ------------------- */
                if (existingLeadC != null) {

                    enquiry.Lead__c = existingLeadC.Id;
                    update enquiry;

                    // Diagram: Check Email Associated
                    EmailDecision ed = handleEmailAssociation(inputData.email, existingLeadC.Id, candidate.Id, enquiry.Id);

                    if (ed == EmailDecision.SAME_LEAD) {
                        markReEnquiry(existingLeadC, enquiry);
                    } else if (ed == EmailDecision.CREATED_AND_ASSOCIATED || ed == EmailDecision.ASSOCIATED_TO_LEAD) {
                        markReEnquiry(existingLeadC, enquiry);
                    } else if (ed == EmailDecision.DIFFERENT_LEAD) {
                        System.debug('Email is with different Lead. Not associating. No re-enquiry marking as per flow.');
                    }

                    leadToReturn = existingLeadC;

                } else {

                    /* ------------------- B2: LEAD NOT EXIST (Phone + Source) ------------------- */
                    // Not Exist -> Create New Lead with course and tag phone number also

                    Lead__c newLead2 = new Lead__c(
                        Name                     = inputData.first_name,
                        Phone__c                 = inputData.phone,
                        Email__c                 = inputData.email,
                        Stage__c                 = 'M3',
                        Course__c                = inputData.course,
                        Source__c                = inputData.coming_from,
                        Register_for_Webinar__c  = inputData.register_for_webinar,
                        Interested_Webinar_ID__c = inputData.interested_webinar_id,
                        Candidate__c             = candidate.Id
                    );
                    insert newLead2;

                    // Tag phone number also (reuse existing if found)
                    List<Phone_Number__c> phoneList = [
                        SELECT Id, Candidate__c, Lead__c
                        FROM Phone_Number__c
                        WHERE Phone__c = :inputData.phone
                        LIMIT 1
                    ];

                    if (phoneList.isEmpty()) {
                        Phone_Number__c newPhone = new Phone_Number__c(
                            Name         = inputData.phone,
                            Phone__c     = inputData.phone,
                            Candidate__c = candidate.Id,
                            Lead__c      = newLead2.Id
                        );
                        insert newPhone;
                    } else {
                        Phone_Number__c ph = phoneList[0];
                        if (ph.Candidate__c == null) ph.Candidate__c = candidate.Id;
                        ph.Lead__c = newLead2.Id;
                        update ph;
                    }

                    enquiry.Lead__c = newLead2.Id;
                    update enquiry;

                    leadToReturn = newLead2;

                    // Check Email Associated
                    EmailDecision ed = handleEmailAssociation(inputData.email, newLead2.Id, candidate.Id, enquiry.Id);

                    if (ed == EmailDecision.DIFFERENT_LEAD) {
                        System.debug('Email exists with different Lead. Not associating (as per flow).');
                    }
                    
                }
            }

            /* ------------------- CREATE FOLLOW-UP TASK ------------------- */
            String taskSubject = 'Follow Up Call';
           // Task t = MilesExistingEnquiryWebService.createFollowUpTask(enquiry, taskSubject);

            res.statusCode = 201;
            return JSON.serialize(
                new ApiResponse(true, 'Enquiry processed as per flow.', leadToReturn != null ? leadToReturn.Id : null)
            );

        } catch (Exception ex) {
            System.debug('MilesWebService Error => ' + ex.getMessage() + ' :: ' + ex.getStackTraceString());
            RestContext.response.statusCode = 500;

            IntegrationLogUtil.insertLogs(new List<Integration_Log__c>{
                IntegrationLogUtil.buildLog('Enquiry', null, null, 'Error: ' + ex.getMessage(), 'FAILED', null)
            });

            return JSON.serialize(new ApiResponse(false, 'Error: ' + ex.getMessage(), null));
        }
    }

    private static EmailDecision handleEmailAssociation(String email, Id leadId, Id candidateId, Id enquiryId) {

        if (String.isBlank(email) || leadId == null) {
            System.debug('Email association skipped: blank email or leadId is null');
            return null;
        }

        List<Email__c> emailList = [SELECT Id, Lead__c, Candidate__c FROM Email__c WHERE Email__c = :email LIMIT 1 ];

        // Email exists
        if (!emailList.isEmpty()) {
            Email__c existingEmail = emailList[0];

            // With Different Lead -> Don't associate
            if (existingEmail.Lead__c != null && existingEmail.Lead__c != leadId) {
                System.debug('Email__c found linked to DIFFERENT Lead. Not associating.');
                return EmailDecision.DIFFERENT_LEAD;
            }

            // With Same Lead
            if (existingEmail.Lead__c == leadId) {
                System.debug('Email__c found linked to SAME Lead.');
                return EmailDecision.SAME_LEAD;
            }

            // Email exists but Lead__c is null -> safe to associate
            existingEmail.Lead__c      = leadId;
            if (existingEmail.Candidate__c == null) existingEmail.Candidate__c = candidateId;
            // if (existingEmail.Enquiry__c == null)   existingEmail.Enquiry__c   = enquiryId;
            update existingEmail;

            System.debug('Email__c existed but was unlinked. Now associated.');
            return EmailDecision.ASSOCIATED_TO_LEAD;
        }

        // Email Not Exist in SF -> Create email and associate
        Email__c newEmail = new Email__c(
            Email__c         = email,
            Lead__c          = leadId,
            Candidate__c     = candidateId
            // Enquiry__c       = enquiryId
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