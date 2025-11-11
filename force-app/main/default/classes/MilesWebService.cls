@RestResource(urlMapping='/milessite/*')
global without sharing class MilesWebService {

    private static final String EXPECTED_SECURITY_CODE = 'MY_SECURE_CODE_123';

    @HttpPost
    global static String doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            // Validate Security Code 
            String securityCode = req.headers.get('securityCode');
            if (String.isBlank(securityCode)) {
                res.statusCode = 400;
                return 'Missing required header: securityCode';
            }
            if (securityCode != EXPECTED_SECURITY_CODE) {
                res.statusCode = 401;
                return 'Unauthorized: Invalid security code';
            }

            // Validate Request Body 
            String requestBody = req.requestBody != null ? req.requestBody.toString() : '';
            if (String.isBlank(requestBody)) {
                res.statusCode = 400;
                return 'Request body is empty';
            }

            //  Log the Request 
            IntegrationLogUtil.insertLogs(new List<Integration_Log__c>{
                IntegrationLogUtil.buildLog('Enquiry', requestBody, null, null, 'SUCCESS', null)
            });

            // Deserialize Request Body 
            EnquiryWrapper inputData = (EnquiryWrapper) JSON.deserialize(requestBody, EnquiryWrapper.class);

            // Validate Required Fields 
            if (String.isBlank(inputData.first_name) || String.isBlank(inputData.phone)) {
                res.statusCode = 400;
                return 'Missing required fields: first_name or phone';
            }

            // -Create Enquiry Record 
            Boolean whatsappAllow = (inputData.whatsappAllow != null && inputData.whatsappAllow == 1);
            Enquiry__c enquiry = new Enquiry__c(
                First_Name__c = inputData.first_name,
                Phone_Number__c = inputData.phone,
                Email__c = inputData.email,
                City__c = inputData.city,
                Course__c = inputData.course,
                City_Id__c = inputData.city_id,
                SMS_Allow__c = (inputData.smsAllow == 1),
                Coming_From__c = inputData.coming_from,
                WhatsApp_Allow__c = whatsappAllow,
                WhatsApp_Opt_In__c = inputData.whatsapp_opt_in,
                Highest_Education__c = inputData.highestEducation,
                Country_of_Residence__c = inputData.country_of_residence,
                Register_for_Webinar__c = inputData.register_for_webinar,
                Interested_Webinar_ID__c = inputData.interested_webinar_id,
                Stage__c = 'M3'
            );
            insert enquiry;

            // Check for Existing Phone Number ---
            List<Phone_Number__c> existingPhones = [
                SELECT Id, Lead__c
                FROM Phone_Number__c
                WHERE Phone__c = :inputData.phone
                LIMIT 1
            ];

            if (!existingPhones.isEmpty()) {
                res.statusCode = 200;
                return JSON.serialize(
                    new ApiResponse(false, 'Phone number already exists', existingPhones[0].Lead__c)
                );
            }

            //  Create Lead
            Lead newLead = new Lead(
                FirstName = inputData.first_name,
                LastName = inputData.first_name,
                Company = 'Test Company',
                Phone = inputData.phone,
                Email = inputData.email,
                Coming_From__c = inputData.coming_from,
                Register_for_Webinar__c = inputData.register_for_webinar,
                Interested_Webinar_ID__c = inputData.interested_webinar_id
            );
            insert newLead;

            //Create Phone Number Record and Link to Lead 
            Phone_Number__c phoneRecord = new Phone_Number__c(
                Phone__c = inputData.phone,
                Lead__c = newLead.Id
            );
            insert phoneRecord;

            // Link back to Lead if Lead has a lookup to Phone_Number__c
            if (Schema.sObjectType.Lead.fields.getMap().containsKey('Phone_Number__c')) {
                newLead.Phone_Number__c = phoneRecord.Id;
                update newLead;
            }
            
            
           enquiry.Lead__c = newLead.Id;
           update enquiry;


            // City update handled automatically by trigger
            res.statusCode = 201;
           return JSON.serialize(
    new ApiResponse(true, 'Enquiry & Lead created successfully.', newLead.Id)
);

        } catch (Exception ex) {
            res.statusCode = 500;
            return JSON.serialize(new ApiResponse(false, 'Error: ' + ex.getMessage(), null));
        }
    }

    // Wrapper Classes 
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
    }

    global class ApiResponse {
        public Boolean success;
        public String message;
        public String recordId;
        public ApiResponse(Boolean success, String message, String recordId) {
            this.success = success;
            this.message = message;
            this.recordId = recordId;
        }
    }
}