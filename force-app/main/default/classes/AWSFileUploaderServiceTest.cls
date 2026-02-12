@isTest
public class AWSFileUploaderServiceTest {
    @isTest
    static void testAppendUrls() {
        Lead testLead = TestDataFactory.createLead('Test', 'Company', 'Open');
        
        List<AWSFileUploaderService.S3Url> items = new List<AWSFileUploaderService.S3Url>();
        AWSFileUploaderService.S3Url item1 = new AWSFileUploaderService.S3Url();
        item1.name = 'TestFile';
        item1.url = 'https://example.com/file';
        items.add(item1);
        
        Test.startTest();
        AWSFileUploaderService.appendUrls('Lead', testLead.Id, items, 'Description');
        Test.stopTest();
        
        Lead updatedLead = [SELECT Description FROM Lead WHERE Id = :testLead.Id];
        System.assert(updatedLead.Description.contains('https://example.com/file'), 'URL should be appended to Description');
        System.assert(updatedLead.Description.contains('TestFile'), 'Name should be appended to Description');
    }

    @isTest
    static void testAppendUrlsJson() {
        Lead testLead = TestDataFactory.createLead('Test', 'Company', 'Open');
        String itemsJson = '[{"name":"TestFileJSON", "url":"https://example.com/json"}]';
        
        Test.startTest();
        AWSFileUploaderService.appendUrlsCtx('Lead', testLead.Id, itemsJson, 'Description', 'AWS');
        Test.stopTest();
        
        Lead updatedLead = [SELECT Description FROM Lead WHERE Id = :testLead.Id];
        System.assert(updatedLead.Description.contains('https://example.com/json'), 'URL should be appended');
        System.assert(updatedLead.Description.contains('[AWS]'), 'Context should be prepended');
    }

    @isTest
    static void testInvalidObject() {
        try {
            AWSFileUploaderService.appendUrls('InvalidObject', null, null, 'Field');
        } catch (Exception e) {
            System.assert(e instanceof AuraHandledException, 'Should throw AuraHandledException for invalid object');
        }
    }
}