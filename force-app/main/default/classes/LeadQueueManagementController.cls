public class LeadQueueManagementController {

	public class LeadRow{
		@AuraEnabled Public Id id;
		@AuraEnabled Public String name;
		@AuraEnabled Public String phone;
		@AuraEnabled Public String source;
		@AuraEnabled Public String city;
	}

	@AuraEnabled(cacheable=true)
	public static List<LeadRow> getUserLeads (){
		List<LeadRow> result = new List<LeadRow>();
		for(Lead l : [SELECT Id,Name,Phone,LeadSource,City from lead where OwnerId = :UserInfo.getUserId() Order by CreatedDate  DESC LIMIT 200]){
			LeadRow row = new LeadRow();
			row.id = l.Id;
			row.name =l.Name;
			row.phone =l.Phone;
			row.source = l.LeadSource;
			row.city = l.City;
			result.add(row);
		}

		return result;
	}
}