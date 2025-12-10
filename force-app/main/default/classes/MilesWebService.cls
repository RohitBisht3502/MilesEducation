/*
    Author             : ROHIT SINGH BISHT
    Description        : 
    Last Modified      : ROHIT SINGH BISHT
    Last Modified Date : 1 DEC 2025
*/
@RestResource(urlMapping='/milessite/*')
global without sharing class MilesWebService {

    private static final String EXPECTED_SECURITY_CODE = 'MY_SECURE_CODE_123';

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
            String requestBody = req.requestBody != null ? req.requestBody.toString() : '';
            if (String.isBlank(requestBody)) {
                res.statusCode = 400;
                return 'Request body is empty';
            }

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

            /* 1. CHECK CANDIDATE (BY PHONE) */
            Lead candidate;
            List<Lead> candidateList = [SELECT Id, Phone FROM Lead WHERE Phone = :inputData.phone LIMIT 1];
            if (!candidateList.isEmpty()) {
                candidate = candidateList[0];
            }

            Lead__c leadToReturn;

            /* ------------------- NO CANDIDATE ------------------- */
            if (candidate == null) {

                // (a) Create Candidate (Lead)
                candidate = new Lead(
                   // FirstName                = inputData.first_name,
                    LastName                 = inputData.first_name,
                    Company                  = 'Test Company',
                    Phone                    = inputData.phone,
                    Email                    = inputData.email,
                    Coming_From__c           = inputData.coming_from,
                    Register_for_Webinar__c  = inputData.register_for_webinar,
                    Interested_Webinar_ID__c = inputData.interested_webinar_id
                );
                insert candidate;

                // (b) Create Phone_Number__c mapped with Candidate
                Phone_Number__c phoneRec = new Phone_Number__c(
                    Name         = inputData.phone,
                    Phone__c     = inputData.phone,
                    Candidate__c = candidate.Id
                );
                insert phoneRec;

                // (c) Create Lead__c with course + phone
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

                // (d) Tag phone record with this Lead__c
                phoneRec.Lead__c = newLead.Id;
                update phoneRec;

                // (e) Link Enquiry
                enquiry.Candidate__c = candidate.Id;
                enquiry.Lead__c      = newLead.Id;
                update enquiry;

                leadToReturn = newLead;

            } else {
                /* ------------------- CANDIDATE EXISTS ------------------- */

                enquiry.Candidate__c = candidate.Id;
                update enquiry;

                // 2. Check Lead__c with same Phone + Course
                Lead__c existingLeadC;
                List<Lead__c> leadCs = [SELECT Id, Stage__c FROM Lead__c WHERE Phone__c = :inputData.phone AND Course__c  = :inputData.course LIMIT 1 ];
                if (!leadCs.isEmpty()) {
                    existingLeadC = leadCs[0];
                }

                if (existingLeadC != null) {
                    // (2A) Lead exists → mark as ReEnquiry
                    existingLeadC.Is_ReEnquiry__c = true;
                    update existingLeadC;

                    enquiry.Lead__c = existingLeadC.Id;
                    // safely set enquiry as ReEnquiry if field exists
                    enquiry.put('Is_ReEnquiry__c', true);
                    update enquiry;

                    leadToReturn = existingLeadC;
                } else {
                    // (2B) No Lead__c for this phone+course → Create new
                    Lead__c newLead2 = new Lead__c(
                        Name                     = inputData.first_name,
                        Phone__c                 = inputData.phone,
                        Email__c                 = inputData.email,
                        Stage__c                 = 'M3',
                        Course__c                = inputData.course,
                        Register_for_Webinar__c  = inputData.register_for_webinar,
                        Interested_Webinar_ID__c = inputData.interested_webinar_id,
                        Source__c                = inputData.coming_from,
                        Candidate__c             = candidate.Id
                    );
                    insert newLead2;

                    // Tag phone number also
                    List<Phone_Number__c> phoneList = [SELECT Id, Candidate__c, Lead__c FROM Phone_Number__c WHERE Phone__c = :inputData.phone LIMIT 1 ];

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
                        ph.Lead__c = newLead2.Id;
                        update ph;
                    }

                    enquiry.Lead__c = newLead2.Id;
                    update enquiry;

                    leadToReturn = newLead2;
                }
            }

            /* ------------------- CREATE FOLLOW-UP TASK ------------------- */
            String taskSubject = 'Follow Up Call';
            Task t = MilesExistingEnquiryWebService.createFollowUpTask(enquiry, taskSubject);

            res.statusCode = 201;
            return JSON.serialize(
                new ApiResponse(true, 'Enquiry processed as per flow.', leadToReturn != null ? leadToReturn.Id : null)
            );

        } catch (Exception ex) {
            res.statusCode = 500;
            return JSON.serialize(new ApiResponse(false, 'Error: ' + ex.getMessage(), null));
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