// Utility to extract qualification info from file paths coming from Datalake.
public without sharing class EligibilityPathParser {

    public class ParsedPath {
        public String qualificationType; // UG / PG / Certification
        public String qualificationTitle; // e.g., B.Tech
        public String category; // certificates / mark_sheets
        public String fileName;
        public Boolean isFlat;
        public String flatFolderKey; // resume / work_experience
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
            if (parts[i] != null && (
                parts[i].toLowerCase() == 'eligibility_docs' ||
                parts[i].toLowerCase() == 'eligibility_doc'
            )) {
                idx = i;
                break;
            }
        }
        if (idx == -1 || idx + 1 >= parts.size()) {
            return null;
        }

        ParsedPath p = new ParsedPath();
        String flatKeyCandidate = normalizeFlatFolderKey(parts[idx + 1]);
        if (String.isNotBlank(flatKeyCandidate)) {
            // Flat structure: .../eligibility_docs/{resume|work_experience}/...
            p.isFlat = true;
            p.flatFolderKey = flatKeyCandidate;
            p.qualificationType = parts[idx + 1];
            p.qualificationTitle = null;
            p.category = null;
            p.fileName = parts[parts.size() - 1];
        } else if (idx + 4 < parts.size()) {
            // Expecting .../eligibility_docs/{type}/{title}/{category}/...
            p.qualificationType = parts[idx + 1];
            p.qualificationTitle = parts[idx + 2];
            p.category = parts[idx + 3];
            p.fileName = parts[parts.size() - 1];
            p.isFlat = false;
            p.flatFolderKey = null;
        } else {
            return null;
        }
        return p;
    }

    public static String categoryToLogicalType(String category) {
        if (String.isBlank(category)) return null;
        String c = category.toLowerCase();
        if (c.contains('certificate')) return 'Certificate';
        if (c.contains('mark')) return 'Marksheet';
        return null;
    }

    public static String normalizeFlatFolderKey(String raw) {
        if (String.isBlank(raw)) return null;
        String key = raw.trim().toLowerCase();
        key = key.replace(' ', '_').replace('-', '_');
        if (key == 'resume') return 'resume';
        if (key == 'work_experience' || key == 'workexperience' || key == 'work__experience') return 'work_experience';
        return null;
    }

    public static String flatFolderLabel(String rawKey) {
        String key = normalizeFlatFolderKey(rawKey);
        if (key == 'resume') return 'Resume';
        if (key == 'work_experience') return 'Work Experience';
        return null;
    }
}