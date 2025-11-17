/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class DTORunoCallLogs {
    public String processId;
    public String userPhone;
    public Long createdAt;
    public String tag;
    public String type;
    public Integer duration;
    public Long startTime;
    public String phoneNumber;
    public String customerId;
    public String name;
    public String calledBy;
    public String callerId;
    public String callId;
    public String status;

    private static Datetime fromEpoch(Long s) {
        return s == null ? null : Datetime.newInstance(1970, 1, 1, 0, 0, 0).addSeconds((Integer)s);
    }

    private static Id leadByPhone(String p) {
        if (String.isBlank(p)) return null;
        String d = p.replaceAll('[^0-9]', '');
        if (d.startsWith('91')) d = d.substring(2);
        if (d.length() > 10) d = d.right(10);
        List<Lead> ls = [SELECT Id FROM Lead WHERE Phone != null AND Phone LIKE :('%' + d) LIMIT 1];
        return ls.isEmpty() ? null : ls[0].Id;
    }

    public Call_Log__c toSObject(String raw) {
        Call_Log__c c = new Call_Log__c();
        c.Call_Id__c = callId;
        c.Process_Id__c = processId;
        c.User_Phone__c = userPhone;
        c.Phone_Number__c = phoneNumber;
        c.Customer_Id__c = customerId;
        c.Customer_Name__c = name;
        c.Called_By__c = calledBy;
        c.Caller_Id__c = callerId;
        c.Tag__c = tag;
        c.Type__c = type;
        c.Duration_Seconds__c = duration;
        c.Created_At__c = fromEpoch(createdAt);
        c.Start_Time__c = fromEpoch(startTime);
        c.Status__c = status;
        System.debug('leadByPhone(phoneNumber)  '+leadByPhone(phoneNumber));
        c.Lead__c = leadByPhone(phoneNumber);
        return c;
    }

    public static List<Call_Log__c> toRecords(String body) {
        Object o = JSON.deserializeUntyped(body);
        List<Call_Log__c> out = new List<Call_Log__c>();
        if (o instanceof List<Object>) {
            List<Object> arr = (List<Object>)o;
            for (Object item : arr) {
                DTORunoCallLogs dto = (DTORunoCallLogs)JSON.deserialize(JSON.serialize(item), DTORunoCallLogs.class);
                out.add(dto.toSObject(JSON.serialize(item)));
            }
        } else {
            DTORunoCallLogs dto = (DTORunoCallLogs)JSON.deserialize(body, DTORunoCallLogs.class);
            out.add(dto.toSObject(body));
        }
        return out;
    }
}