// Utility to extract qualification info from file paths coming from Datalake.
public without sharing class EligibilityPathParser {

    public class ParsedPath {
        public String qualificationType; // UG / PG / Certification
        public String qualificationTitle; // e.g., B.Tech
        public String category; // certificates / mark_sheets
        public String fileName;
    }

    public static ParsedPath parse(String rawPath) {
        if (String.isBlank(rawPath)) {
            return null;
        }

        String normalized = rawPath.replace('\\', '/');
        List<String> parts = normalized.split('/');
        if (parts.isEmpty()) {
            return null;
        }

        Integer idx = -1;
        for (Integer i = 0; i < parts.size(); i++) {
            if (parts[i] != null && parts[i].toLowerCase() == 'eligibility_docs') {
                idx = i;
                break;
            }
        }
        if (idx == -1 || idx + 3 >= parts.size()) {
            // Expecting .../eligibility_docs/{type}/{title}/{category}/...
            return null;
        }

        ParsedPath p = new ParsedPath();
        p.qualificationType = parts[idx + 1];
        p.qualificationTitle = parts[idx + 2];
        p.category = parts[idx + 3];
        p.fileName = parts[parts.size() - 1];
        return p;
    }

    public static String categoryToLogicalType(String category) {
        if (String.isBlank(category)) return null;
        String c = category.toLowerCase();
        if (c.contains('certificate')) return 'Certificate';
        if (c.contains('mark')) return 'Marksheet';
        return null;
    }
}