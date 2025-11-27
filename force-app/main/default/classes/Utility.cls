/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public class Utility {

    public static Id candidateByPhone(String p) {
        if (String.isBlank(p)) return null;
        String d = p.replaceAll('[^0-9]', '');
        if (d.startsWith('91')) d = d.substring(2);
        if (d.length() > 10) d = d.right(10);
        List<Lead> ls = [SELECT Id FROM Lead WHERE Phone != null AND Phone LIKE :('%' + d) LIMIT 1];
        return ls.isEmpty() ? null : ls[0].Id;
    }

}