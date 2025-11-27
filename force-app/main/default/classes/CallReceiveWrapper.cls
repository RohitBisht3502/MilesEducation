public class CallReceiveWrapper {

    public String processId;	//68d661d67b41e19800749963
	public String userPhone;	//+918123191110
	public Integer createdAt;	//1763107438
	public String tag;	//unanswered
	public String type;	//outgoing
	public Integer duration;	//0
	public Integer startTime;	//1763107407
	public String phoneNumber;	//+919306384290
	public String customerId;	//6916c4fc0206aa60bb73c2b3
	public String name;	//Mohit test Mohit test
	public String calledBy;	//Athulya
	public String callerId;	//451aa85f-f207-49a5-96c1-f83093f3fbf9
	public String callId;	//6916e25207ddbe73e671f359
	
    public static CallReceiveWrapper parse(String json){
		return (CallReceiveWrapper) System.JSON.deserialize(json, CallReceiveWrapper.class);
	}
}