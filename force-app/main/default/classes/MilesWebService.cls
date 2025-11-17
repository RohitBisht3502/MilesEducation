@RestResource(urlMapping='/milessite/*')
global without sharing class MilesWebService {

    private static final String EXPECTED_SECURITY_CODE = 'MY_SECURE_CODE_123';

    @HttpPost
    global static String doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            String securityCode = req.headers.get('securityCode');
            if (String.isBlank(securityCode)) {
                res.statusCode = 400;
                return 'Missing required header: securityCode';
            }
            if (securityCode != EXPECTED_SECURITY_CODE) {
                res.statusCode = 401;
                return 'Unauthorized: Invalid security code';
            }

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

            // -------- NEW: Find existing STANDARD Lead by phone only --------
            Lead existingStdLead;
            List<Lead> stdLeads = [
                SELECT Id
                FROM Lead
                WHERE Phone = :inputData.phone
                LIMIT 1
            ];
            if (!stdLeads.isEmpty()) {
                existingStdLead = stdLeads[0];
                // Update enquiry with existing standard Lead
                enquiry.Candidate__c = existingStdLead.Id;
            }

            // -------- Existing custom Lead__c logic (now by Phone + Course) --------
            Lead__c existingLeadC;
            List<Lead__c> leadCs = [ SELECT Id FROM Lead__c WHERE Phone__c = :inputData.phone AND Course__c = :inputData.course LIMIT 1 ];
            if (!leadCs.isEmpty()) existingLeadC = leadCs[0];

            Lead__c leadCToUse = existingLeadC;
            if (leadCToUse == null) {
                leadCToUse = new Lead__c(
                    Name      = inputData.first_name,
                    Phone__c  = inputData.phone,
                    Email__c  = inputData.email,
                    Stage__c  = 'M3',
                    Course__c = inputData.course
                );
                insert leadCToUse;
            }

            List<Phone_Number__c> existingPhones = [ SELECT Id, Lead__c FROM Phone_Number__c WHERE Phone__c = :inputData.phone LIMIT 1 ];

            if (!existingPhones.isEmpty()) {
                // Link Enquiry with existing custom Lead__c via Phone_Number__c
                enquiry.Lead__c = existingPhones[0].Lead__c;
                // Candidate__c might already be set from existingStdLead (if found)
                update enquiry;
            } else {
                // No Phone_Number__c entry yet
                // Use existing standard Lead if present, otherwise create a new one
                Lead stdLeadToUse = existingStdLead;

                if (stdLeadToUse == null) {
                    stdLeadToUse = new Lead(
                        FirstName                = inputData.first_name,
                        LastName                 = inputData.first_name,
                        Company                  = 'Test Company',
                        Phone                    = inputData.phone,
                        Email                    = inputData.email,
                        Coming_From__c           = inputData.coming_from,
                        Register_for_Webinar__c  = inputData.register_for_webinar,
                        Interested_Webinar_ID__c = inputData.interested_webinar_id
                    );
                    insert stdLeadToUse;
                }

                Phone_Number__c phoneRecord = new Phone_Number__c(
                    Name         = inputData.phone,
                    Phone__c     = inputData.phone,
                    Candidate__c = stdLeadToUse.Id
                );
                insert phoneRecord;

                if (Schema.sObjectType.Lead.fields.getMap().containsKey('Phone_Number__c')) {
                    stdLeadToUse.Phone_Number__c = phoneRecord.Id;
                    update stdLeadToUse;
                }

                enquiry.Lead__c     = leadCToUse.Id;
                enquiry.Candidate__c = stdLeadToUse.Id;
                update enquiry;
            }

            String taskSubject = 'Follow Up Call';
            Task t = MilesExistingEnquiryWebService.createFollowUpTask(enquiry, taskSubject);

            res.statusCode = 201;
            return JSON.serialize(
                new ApiResponse(true, 'Enquiry created successfully.', leadCToUse.Id)
            );

        } catch (Exception ex) {
            res.statusCode = 500;
            return JSON.serialize(new ApiResponse(false, 'Error: ' + ex.getMessage(), null));
        }
    }

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