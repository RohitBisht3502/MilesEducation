@IsTest
private class MilesWebsiteWebserviceTest {

    //Mock for the City Classifier API call
    private class CityClassifierHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"nearest_city": "Delhi"}');
            res.setStatusCode(200);
            return res;
        }
    }

    // Test 1: Successful Enquiry and Lead Creation with full payload
    @IsTest
    static void testSuccessfulEnquiryAndLeadCreation() {
        Test.setMock(HttpCalloutMock.class, new CityClassifierHttpMock());

        // Prepare realistic input JSON
        Map<String, Object> requestData = new Map<String, Object>{
            'city' => 'Mumbai',
            'email' => 'ugankumaryadav367@gmail.com',
            'phone' => '9652567541',
            'course' => 'CMA',
            'gcl_id' => 'GCL123',
            'city_id' => 110,
            'smsAllow' => 1,
            'course_id' => 3,
            'first_name' => 'Ugan Kumar',
            'campaign_tk' => 'CMP12345',
            'coming_from' => 'website-contact_us',
            'nationality' => 'Indian',
            'page_full_url' => 'https://mileseducation.com/data-science',
            'url_page_path' => '/data-science',
            'user_track_id' => 'TRACK001',
            'whatsappAllow' => 1,
            'whatsapp_opt_in' => true,
            'highestEducation' => 'B.Tech',
            'country_of_residence' => 'India',
            'register_for_webinar' => true,
            'interested_webinar_id' => 'WEBINAR001'
        };

        // Create REST Request
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/miles/';
        req.httpMethod = 'POST';
        req.addHeader('securityCode', 'MY_SECURE_CODE_123');
        req.requestBody = Blob.valueOf(JSON.serialize(requestData));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        String result = MilesWebsiteWebservice.doPost();
        Test.stopTest();

        System.debug('Response: ' + result);

        // Basic validation
        System.assert(String.isNotBlank(result), 'Response should not be blank');

        // Verify Enquiry creation
        List<Enquiry__c> enqList = [SELECT Id, First_Name__c, Email__c, Coming_From__c FROM Enquiry__c WHERE Email__c = 'ugankumaryadav367@gmail.com'];
        System.assertEquals(1, enqList.size(), 'One Enquiry record should be created');
        System.assertEquals('Ugan Kumar', enqList[0].First_Name__c, 'First name should match input');

        // Verify Lead creation
        List<Lead> leadList = [SELECT Id, Email, Phone, Coming_From__c FROM Lead WHERE Email = 'ugankumaryadav367@gmail.com'];
        System.assertEquals(1, leadList.size(), 'One Lead record should be created');
        System.assertEquals('website-contact_us', leadList[0].Coming_From__c, 'Lead Coming_From__c should match input');
    }

    //Test 2: Missing Security Header
    @IsTest
    static void testMissingSecurityHeader() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/miles/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"first_name":"Test"}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        String response = MilesWebsiteWebservice.doPost();
        Test.stopTest();

        System.debug('Missing Security Header Response: ' + response);
        System.assert(response.contains('Missing required header'), 'Should mention missing header');
    }

    //Test 3: Invalid Security Code
    @IsTest
    static void testInvalidSecurityCode() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/miles/';
        req.httpMethod = 'POST';
        req.addHeader('securityCode', 'WRONG_CODE');
        req.requestBody = Blob.valueOf('{"first_name":"Test","email":"t@t.com","phone":"999"}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        String response = MilesWebsiteWebservice.doPost();
        Test.stopTest();

        System.debug('Invalid Security Code Response: ' + response);
        System.assert(response.contains('Unauthorized'), 'Should indicate unauthorized');
    }
    
    // test duplicate phone number
@IsTest
static void testDuplicatePhoneNumber() {
    Test.setMock(HttpCalloutMock.class, new CityClassifierHttpMock());

    // Step 1: Insert an existing Lead with same phone to trigger duplicate logic
    Lead existingLead = new Lead(
        LastName = 'Existing User',
        Email = 'existing@example.com',
        Phone = '9652567541',
        City__c = 'Mumbai',
        Coming_From__c = 'website-contact_us',
        Company  = 'test company'
    );
    insert existingLead;

    // Step 2: Prepare same phone data for API request
    Map<String, Object> requestData = new Map<String, Object>{
        'first_name' => 'Duplicate User',
        'email' => 'duplicate@example.com',
        'phone' => '9652567541', // same phone
        'city' => 'Mumbai',
        'Company'  => 'test company',
        'coming_from_c' => 'website-contact_us'
    };

    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/miles/';
    req.httpMethod = 'POST';
    req.addHeader('securityCode', 'MY_SECURE_CODE_123');
    req.requestBody = Blob.valueOf(JSON.serialize(requestData));

    RestContext.request = req;
    RestContext.response = new RestResponse();

    Test.startTest();
    String result = MilesWebsiteWebservice.doPost();
    Test.stopTest();

    System.assert(result.contains('"success":false') || result.contains('"duplicate"'),
        'Expected duplicate phone error response');

    System.debug('Duplicate test result: ' + result);
}


    // Missing Required Fields
    @IsTest
    static void testMissingRequiredFields() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/miles/';
        req.httpMethod = 'POST';
        req.addHeader('securityCode', 'MY_SECURE_CODE_123');
        req.requestBody = Blob.valueOf('{}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        String result = MilesWebsiteWebservice.doPost();
        Test.stopTest();

        System.debug('Missing Fields Response: ' + result);
        System.assert(result.contains('Missing required fields'), 'Should mention missing required fields');
    }
}