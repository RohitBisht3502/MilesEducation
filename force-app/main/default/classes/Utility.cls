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

    public static Set<String> buildPhoneVariants(String rawPhone) {

        Set<String> variants = new Set<String>();

        // Guard clause – no phone provided
        if (String.isBlank(rawPhone)) {
            System.debug(LoggingLevel.WARN,
                'buildPhoneVariants | Raw phone is blank, returning empty variant set'
            );
            return variants;
        }

        // Remove all non-numeric characters (+, spaces, hyphens, brackets, etc.)
        String digits = rawPhone.replaceAll('[^0-9]', '');

        if (String.isBlank(digits)) {
            System.debug(LoggingLevel.WARN,
                'buildPhoneVariants | Raw phone produced no digits. rawPhone=' + rawPhone
            );
            return variants;
        }

        // Base variants
        variants.add(digits);

        // Remove leading zeros (e.g. 09560682867 → 9560682867)
        String noLeadingZeros = digits;
        while (noLeadingZeros.startsWith('0') && noLeadingZeros.length() > 1) {
            noLeadingZeros = noLeadingZeros.substring(1);
        }
        variants.add(noLeadingZeros);

        // CRITICAL: Always include last 10 digits when possible
        if (noLeadingZeros.length() >= 10) {
            String last10 = noLeadingZeros.substring(noLeadingZeros.length() - 10);

            variants.add(last10);          // canonical
            variants.add('0' + last10);    // legacy 0XXXXXXXXXX
            variants.add('91' + last10);   // legacy 91XXXXXXXXXX
            variants.add('+91' + last10);   // legacy 91XXXXXXXXXX

            System.debug(LoggingLevel.INFO,
                'buildPhoneVariants | Normalized phone. raw=' + rawPhone +
                ', last10=' + last10
            );
        } else {
            System.debug(LoggingLevel.WARN,
                'buildPhoneVariants | Phone length < 10 after normalization. raw=' +
                rawPhone + ', digits=' + digits
            );
        }

        System.debug(LoggingLevel.DEBUG,
            'buildPhoneVariants | Final variants=' + variants
        );

        return variants;
    }
}