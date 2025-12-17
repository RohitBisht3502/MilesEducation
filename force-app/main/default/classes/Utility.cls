/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public without sharing class Utility {

    public static Id candidateByPhone(String p) {
        if (String.isBlank(p)) return null;
        String d = p.replaceAll('[^0-9]', '');
        if (d.startsWith('91')) d = d.substring(2);
        if (d.length() > 10) d = d.right(10);
        List<Lead> ls = [SELECT Id FROM Lead WHERE Phone != null AND Phone LIKE :('%' + d) LIMIT 1];
        return ls.isEmpty() ? null : ls[0].Id;
    }

    public static DateTime parseIsoDateTime(String s) {
        if (String.isBlank(s)) return null;

        String t = s.trim();

        if (t.endsWith('Z')) {
            String base = t.substring(0, t.length() - 1);
            if (base.contains('.')) base = base.substring(0, base.indexOf('.'));
            return DateTime.valueOfGmt(base.replace('T', ' '));
        }

        Integer plusIdx = t.lastIndexOf('+');
        Integer minusIdx = t.lastIndexOf('-');
        Integer tzIdx = Math.max(plusIdx, minusIdx);

        if (tzIdx > 18) {
            String base = t.substring(0, tzIdx);
            String off = t.substring(tzIdx);

            if (base.contains('.')) base = base.substring(0, base.indexOf('.'));
            DateTime localDt = DateTime.valueOf(base.replace('T', ' '));

            if (off.length() >= 6 && off.contains(':')) {
                Integer sign = off.startsWith('-') ? -1 : 1;
                Integer hh = Integer.valueOf(off.substring(1, 3));
                Integer mm = Integer.valueOf(off.substring(4, 6));
                Integer offsetMins = sign * (hh * 60 + mm);
                return localDt.addMinutes(-offsetMins);
            }
            return localDt;
        }

        String base2 = t;
        if (base2.contains('.')) base2 = base2.substring(0, base2.indexOf('.'));
        return DateTime.valueOf(base2.replace('T', ' '));
    }


}