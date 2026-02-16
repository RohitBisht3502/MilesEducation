@IsTest
public class RunoCallIdentityServiceTest {

    // Helper method to get Lead Record Type Id
    private static Id getLeadRecordTypeId() {
        RecordType rt = [SELECT Id FROM RecordType 
                         WHERE SObjectType='Lead__c' 
                         ORDER BY CreatedDate ASC LIMIT 1];
        return rt.Id;
    }

    // Helper method to get Course_Enrolled Record Type Id
    private static Id getCourseEnrolledRecordTypeId() {
        RecordType rt = [SELECT Id FROM RecordType 
                         WHERE SObjectType='Course_Enrolled__c' 
                         ORDER BY CreatedDate ASC LIMIT 1];
        return rt.Id;
    }

   /* @IsTest
    static void testGetIdentityWithLead() {
        Id leadRtId = getLeadRecordTypeId();

        Lead__c leadRec = new Lead__c(
            Name = 'Test Lead',
            Email__c = 'lead@test.com',
            Phone__c = '1234567890',
            City__c = 'Delhi',
            Is_ReEnquiry__c = true,
            RecordTypeId = leadRtId,
            Course__c = 'CMA',   // exact picklist value
            Stage__c  = 'M1'     // exact picklist value
        );
        insert leadRec;

        Test.startTest();
        RunoCallIdentityService.IdentityDTO dto = 
            RunoCallIdentityService.getIdentity(leadRec.Id);
        Test.stopTest();

        System.assertNotEquals(null, dto, 'DTO should not be null');
        System.assertEquals('Test Lead', dto.name);
        System.assertEquals('lead@test.com', dto.email);
        System.assertEquals('1234567890', dto.phone);
        System.assertEquals('Delhi', dto.city);
        System.assertEquals('CMA', dto.source);
        System.assertEquals('M1', dto.stage);
        System.assertEquals('Yes', dto.mhpTag);
        System.assertEquals(UserInfo.getUserName(), dto.leadOwner);
        System.assertEquals(null, dto.canId, 'CAN_ID__c is read-only, should be null');
    }
*/

  /*  @IsTest
    static void testGetIdentityWithCourseEnrolled() {
        Id ceRtId = getCourseEnrolledRecordTypeId();

        Course_Enrolled__c ceRec = new Course_Enrolled__c(
            Phone__c = '9876543210',
            City__c = 'Mumbai',
            RecordTypeId = ceRtId,
            Course__c = 'CMA',   // exact picklist value
            Stages__c = 'M1'     // exact picklist value
        );
        insert ceRec;

        Test.startTest();
        RunoCallIdentityService.IdentityDTO dto = 
            RunoCallIdentityService.getIdentity(ceRec.Id);
        Test.stopTest();

        System.assertNotEquals(null, dto, 'DTO should not be null');
        System.assertEquals('NA', dto.email);
        System.assertEquals('9876543210', dto.phone);
        System.assertEquals('Mumbai', dto.city);
        System.assertEquals('CMA', dto.source);
        System.assertEquals('M1', dto.stage);
        System.assertEquals(null, dto.canId);
    }
*/
    @IsTest
    static void testGetIdentityWithCallLog() {
        Call_Log__c callRec = new Call_Log__c(
            Customer_Name__c = 'Customer Test',
            Phone_Number__c = '5555555555'
        );
        insert callRec;

        Test.startTest();
        RunoCallIdentityService.IdentityDTO dto = 
            RunoCallIdentityService.getIdentity(callRec.Id);
        Test.stopTest();

        System.assertNotEquals(null, dto, 'DTO should not be null');
        System.assertEquals('Customer Test', dto.name);
        System.assertEquals('NA', dto.email);
        System.assertEquals('5555555555', dto.phone);
        System.assertEquals('NA', dto.city);
        System.assertEquals('NA', dto.source);
        System.assertEquals('NA', dto.stage);
        System.assertEquals(null, dto.canId);
    }

    @IsTest
    static void testGetIdentityWithNullId() {
        Test.startTest();
        RunoCallIdentityService.IdentityDTO dto = 
            RunoCallIdentityService.getIdentity(null);
        Test.stopTest();

        System.assertEquals(null, dto, 'DTO should be null when recordId is null');
    }

  @IsTest
    static void testGetCourseIdentityWrapper() {
        Id leadRtId = getLeadRecordTypeId();

        Lead__c leadRec = new Lead__c(
            Name = 'Wrapper Lead',
            Email__c = 'wrapper@test.com',
            RecordTypeId = leadRtId
        );
        insert leadRec;

        Test.startTest();
        RunoCallIdentityService.IdentityDTO dto = 
            RunoCallIdentityService.getCourseIdentity(leadRec.Id);
        Test.stopTest();

        System.assertNotEquals(null, dto, 'DTO from wrapper should not be null');
        System.assertEquals('Wrapper Lead', dto.name);
        System.assertEquals('wrapper@test.com', dto.email);
    }
}