public with sharing class AWSFileUploaderService {
    @AuraEnabled
    public static void appendUrls(String objectApiName, Id recordId, Object items, String urlsFieldApiName) {
        appendUrlsCtx(objectApiName, recordId, items, urlsFieldApiName, null);
    }

    @AuraEnabled
    public static void appendUrlsCtx(String objectApiName, Id recordId, Object items, String urlsFieldApiName, String context) {
        if (String.isBlank(objectApiName) || recordId == null || items == null || String.isBlank(urlsFieldApiName)) return;
        List<S3Url> parsedItems = new List<S3Url>();
        try {
            if (items instanceof List<Object>) {
                for (Object o : (List<Object>)items) {
                    Map<String, Object> m = (Map<String, Object>)JSON.deserializeUntyped(JSON.serialize(o));
                    S3Url s = new S3Url();
                    s.name = (String)m.get('name');
                    s.url = (String)m.get('url');
                    parsedItems.add(s);
                } // hellg
            } else if (items instanceof String) {
                parsedItems = (List<S3Url>)JSON.deserialize((String)items, List<S3Url>.class);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error parsing items: ' + e.getMessage());
        }
        if (parsedItems.isEmpty()) return;
        Schema.SObjectType t = Schema.getGlobalDescribe().get(objectApiName);
        if (t == null) throw new AuraHandledException('Invalid object: ' + objectApiName);
        Map<String, Schema.SObjectField> fmap = t.getDescribe().fields.getMap();
        String field = urlsFieldApiName;
        if (!fmap.containsKey(field)) {
            if (fmap.containsKey(field + '__c')) field = field + '__c';
            else throw new AuraHandledException('Field not found: ' + urlsFieldApiName);
        }
        String soql = 'SELECT Id,' + field + ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';
        SObject rec = Database.query(soql);
        String existing = (String)rec.get(field);
        String addHtml = buildHtml(parsedItems, context);
        String combined = (String.isBlank(existing)) ? addHtml : existing + addHtml;
        rec.put(field, combined);
        update rec;
    }
    public class S3Url {
        @AuraEnabled public String name;
        @AuraEnabled public String url;
    }

    static String buildHtml(List<S3Url> items, String context) {
        String prefix = String.isBlank(context) ? '' : '[' + context.toUpperCase() + '] ';
        String html = '';
        for (S3Url i : items) {
            if (String.isBlank(i.url)) continue;
            String label = String.isBlank(i.name) ? i.url : i.name;
            html += '<div><a href="' + i.url + '" target="_blank" rel="noopener noreferrer">' + prefix + label + '</a></div>';
        }
        return html;
    }
}