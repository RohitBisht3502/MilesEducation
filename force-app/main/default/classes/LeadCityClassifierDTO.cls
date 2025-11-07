public class LeadCityClassifierDTO {
    public class Request {
        public String email;
        public String level;
        public String phone;
        public String country_code;
        public String gcl_id;
        public Integer course_id;
        public String last_name;
        public String first_name;
        public Integer campaign_id;
        public String campaign_tk;
        public String coming_from;
        public String clevertap_id;
        public String linked_in_url;
        public String page_full_url;
        public String url_page_path;
        public Boolean whatsapp_opt_in;
        public Boolean isFromWelcomeBack;
        public Boolean register_for_webinar;
        public Boolean intrested_to_work_in_us;
    }
    public class Root { public Request request; }

    public static String toJsonFromLead(Lead ld) {
        Root r = new Root();
        r.request = new Request();
        r.request.email = ld.Email;
        r.request.phone = ld.Phone;
        r.request.first_name = n(ld.FirstName);
        r.request.last_name = n(ld.LastName);
        r.request.coming_from = n((String)ld.get('Coming_From__c'));
        r.request.country_code = cc(ld.Phone);
        r.request.level = null;
        r.request.gcl_id = ' ';
        r.request.course_id = 3;
        r.request.campaign_id = 1450;
        r.request.campaign_tk = ' ';
        r.request.clevertap_id = '';
        r.request.linked_in_url = '';
        r.request.page_full_url = '';
        r.request.url_page_path = '';
        r.request.whatsapp_opt_in = true;
        r.request.isFromWelcomeBack = false;
        r.request.register_for_webinar = true;
        r.request.intrested_to_work_in_us = true;
        return JSON.serialize(r);
    }

    private static String n(String s){ return s==null?'':s; }

    private static String cc(String p){
        if (String.isBlank(p)) return null;
        String t = p.trim();
        if(!t.startsWith('+')) return null;
        String d = '';
        for(Integer i=1; i<t.length(); i++){
            String c = t.substring(i, i+1);
            if(c >= '0' && c <= '9') d += c;
            else break;
        }
        return String.isBlank(d) ? null : '+' + d;
    }
}