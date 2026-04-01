public class WebinarController {

    @AuraEnabled(cacheable=true)
    public static List<WebinarDTO> getWebinarsByNameOnly() {
        List<WebinarDTO> out = new List<WebinarDTO>();
        Datetime nowDt = System.now();

for (Webinar__c w : [
    SELECT Id, Name, Webinar_Id__c, Topic__c, Agenda__c, Start_Date_Time__c, End_Date_Time__c, Status__c ,Duration__c
    FROM Webinar__c
    WHERE IsActive__c = TRUE
        AND Status__c IN ('Created', 'Started')
        AND Start_Date_Time__c != null
        AND (
            End_Date_Time__c = null 
            OR End_Date_Time__c > :nowDt
        )
    ORDER BY Start_Date_Time__c DESC, Name ASC
    LIMIT 200
]) {
            out.add(toWebinarDTO(w));
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<WebinarDTO> getWebinarsByNameOrId(String searchKey) {
        List<WebinarDTO> out = new List<WebinarDTO>();
        String trimmedSearchKey = String.isBlank(searchKey) ? null : searchKey.trim();
        String key = String.isBlank(trimmedSearchKey) ? null : '%' + trimmedSearchKey + '%';

        List<Webinar__c> webinars;
        if (String.isBlank(key)) {
           Datetime nowDt = System.now();

webinars = [
    SELECT Id, Name, Webinar_Id__c, Topic__c, Agenda__c, Start_Date_Time__c, End_Date_Time__c, Status__c, Duration__c
    FROM Webinar__c
    WHERE IsActive__c = TRUE
        AND Status__c IN ('Created', 'Started')
        AND Start_Date_Time__c != null
        AND (
            End_Date_Time__c = null 
            OR End_Date_Time__c > :nowDt
        )
    ORDER BY Start_Date_Time__c DESC, Name ASC
    LIMIT 200
];
        } else {
            Datetime nowDt = System.now();

webinars = [
    SELECT Id, Name, Webinar_Id__c, Topic__c, Agenda__c, Start_Date_Time__c, End_Date_Time__c, Status__c, Duration__c
    FROM Webinar__c
    WHERE IsActive__c = TRUE
        AND Status__c IN ('Created', 'Started')
        AND Start_Date_Time__c != null
        AND (
            End_Date_Time__c = null 
            OR End_Date_Time__c > :nowDt
        )
        AND (
            Name LIKE :key
            OR Webinar_Id__c LIKE :key
            OR Webinar_Id__c = :trimmedSearchKey
        )
    ORDER BY Start_Date_Time__c DESC, Name ASC
    LIMIT 200
];
        }
for (Webinar__c w : webinars) {
    WebinarDTO dto = toWebinarDTO(w);

    // Skip expired webinars
    if (dto.isExpired) {
        continue;
    }

    out.add(dto);
}

        System.debug('Webinar search results for key "' + searchKey + '": ' + out.size());
        return out;
    }

    @AuraEnabled
    public static Id createWebinarMember(Id recordId, Id webinarId) {
        if (recordId == null || webinarId == null) {
            throw new AuraHandledException('Record and Webinar are required.');
        }

          Lead__c leadRec = [
        SELECT Id, Email__c 
        FROM Lead__c 
        WHERE Id = :recordId 
        LIMIT 1
    ];

    if (String.isBlank(leadRec.Email__c)) {
        throw new AuraHandledException(
            'This Lead does not have an email address. Please add an email before registering for webinar.'
        );
    }

        List<Webinar_Member__c> wmList = [SELECT Id, Lead__c, Enquiry__c, Webinar__c FROM Webinar_Member__c WHERE Webinar__c = :webinarId AND (Lead__c = :recordId OR Enquiry__c = :recordId) LIMIT 1];
        if (!wmList.isEmpty()) {
            throw new AuraHandledException('This record is already registered for this webinar.');
        }

        return System.enqueueJob(new LeadZoomRegistrationJob(recordId, webinarId));
    }

  private static WebinarDTO toWebinarDTO(Webinar__c w) {
    WebinarDTO d = new WebinarDTO();

    d.id = w.Id;
    d.name = w.Name;
    d.webinarId = w.Webinar_Id__c;
    d.topic = w.Topic__c;
    d.agenda = w.Agenda__c;
    d.startDateTime = w.Start_Date_Time__c;
    d.endDateTime = w.End_Date_Time__c;
    d.duration = (Integer) w.Duration__c;
    d.status = w.Status__c;

    //  AUTO CALCULATE END TIME
    if (d.startDateTime != null && d.endDateTime == null && d.duration != null) {
        d.endDateTime = d.startDateTime.addMinutes(d.duration);
    }

    // CHECK EXPIRED
    if (d.endDateTime != null) {
        d.isExpired = d.endDateTime < System.now();
    } else {
        d.isExpired = false;
    }

    return d;
}

    public class WebinarDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String webinarId;
        @AuraEnabled public String topic;
        @AuraEnabled public String agenda;
        @AuraEnabled public DateTime startDateTime;
        @AuraEnabled public DateTime endDateTime;
        @AuraEnabled public Integer duration;
@AuraEnabled public Boolean isExpired;
        @AuraEnabled public String status;
    }

}