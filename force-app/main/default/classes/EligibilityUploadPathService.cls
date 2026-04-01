public without sharing class EligibilityUploadPathService {

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class DegreeOption {
        @AuraEnabled public String typeLabel;
        @AuraEnabled public String typeValue;
        @AuraEnabled public String titleLabel;
        @AuraEnabled public String titleValue;
    }

    public class PathOptions {
        @AuraEnabled public List<PicklistOption> qualificationTypes;
        @AuraEnabled public List<PicklistOption> qualificationTitles;
        @AuraEnabled public List<PicklistOption> categories;
        @AuraEnabled public List<DegreeOption> degreeOptions;
        @AuraEnabled public String uuid;
    }

    @AuraEnabled(cacheable=true)
    public static PathOptions getPathOptions(Id recordId, String uuid) {
        PathOptions res = new PathOptions();
        res.qualificationTypes = new List<PicklistOption>();
        res.qualificationTitles = new List<PicklistOption>();
        res.categories = new List<PicklistOption>();
        res.degreeOptions = new List<DegreeOption>();

        if (recordId == null && String.isBlank(uuid)) {
            return res;
        }

        EligibilityRecordResolver.Context ctx;
        if (recordId != null) {
            ctx = EligibilityRecordResolver.resolveByRecordId(recordId);
        }
        if ((ctx == null || (ctx.studentId == null && ctx.candidateId == null)) && String.isNotBlank(uuid)) {
            ctx = EligibilityRecordResolver.resolveByKey(uuid);
        }
        if (ctx == null || (ctx.studentId == null && ctx.candidateId == null)) {
            return res;
        }
        res.uuid = EligibilityRecordResolver.resolveUuid(ctx);

        List<Eligibility_Folder__c> folders;
        if (ctx.studentId != null && ctx.candidateId != null) {
            folders = [
                SELECT Id, Name, Folder_Type__c, Qualification_Type__c, Degree_Title__c, Level__c
                FROM Eligibility_Folder__c
                WHERE Student__c = :ctx.studentId OR Candidate__c = :ctx.candidateId
            ];
        } else if (ctx.studentId != null) {
            folders = [
                SELECT Id, Name, Folder_Type__c, Qualification_Type__c, Degree_Title__c, Level__c
                FROM Eligibility_Folder__c
                WHERE Student__c = :ctx.studentId
            ];
        } else {
            folders = [
                SELECT Id, Name, Folder_Type__c, Qualification_Type__c, Degree_Title__c, Level__c
                FROM Eligibility_Folder__c
                WHERE Candidate__c = :ctx.candidateId
            ];
        }

        if (folders.isEmpty()) {
            return res;
        }

        Map<String, String> typeLabelByValue = new Map<String, String>();
        for (Eligibility_Folder__c f : folders) {
            if (f.Folder_Type__c == 'QualificationType' && String.isNotBlank(f.Qualification_Type__c)) {
                String label = String.isNotBlank(f.Name) ? f.Name : f.Qualification_Type__c;
                if (!typeLabelByValue.containsKey(f.Qualification_Type__c)) {
                    typeLabelByValue.put(f.Qualification_Type__c, label);
                }
            }
        }

        Map<String, PicklistOption> typeOptionsByValue = new Map<String, PicklistOption>();
        Map<String, PicklistOption> titleOptionsByValue = new Map<String, PicklistOption>();
        Map<String, PicklistOption> categoryOptionsByValue = new Map<String, PicklistOption>();

        for (Eligibility_Folder__c f : folders) {
            String folderType = f.Folder_Type__c != null ? f.Folder_Type__c : '';
            String lowerType = folderType.toLowerCase();

            String flatKey = resolveFlatKey(f);
            if (String.isNotBlank(flatKey)) {
                String label = String.isNotBlank(f.Name) ? f.Name : f.Folder_Type__c;
                addOption(typeOptionsByValue, label, flatKey);
            }

            if (folderType == 'Degree' && String.isNotBlank(f.Degree_Title__c)) {
                String typeValue = f.Qualification_Type__c;
                String typeLabel = String.isNotBlank(typeValue) ? typeLabelByValue.get(typeValue) : null;
                if (String.isBlank(typeLabel)) {
                    typeLabel = typeValue;
                }
                addOption(typeOptionsByValue, typeLabel, typeValue);

                String titleValue = f.Degree_Title__c;
                String titleLabel = String.isNotBlank(f.Name) ? f.Name : titleValue;
                addOption(titleOptionsByValue, titleLabel, titleValue);

                DegreeOption degree = new DegreeOption();
                degree.typeValue = typeValue;
                degree.typeLabel = typeLabel;
                degree.titleValue = titleValue;
                degree.titleLabel = titleLabel;
                res.degreeOptions.add(degree);
            }

            if (lowerType.contains('certificate') || lowerType.contains('mark')) {
                String label = String.isNotBlank(f.Name) ? f.Name : f.Folder_Type__c;
                String value = toPathSegment(String.isNotBlank(f.Folder_Type__c) ? f.Folder_Type__c : label);
                addOption(categoryOptionsByValue, label, value);
            }
        }

        if (typeOptionsByValue.isEmpty() && !typeLabelByValue.isEmpty()) {
            for (String typeValue : typeLabelByValue.keySet()) {
                addOption(typeOptionsByValue, typeLabelByValue.get(typeValue), typeValue);
            }
        }

        res.qualificationTypes = sortOptions(typeOptionsByValue.values());
        res.qualificationTitles = sortOptions(titleOptionsByValue.values());
        res.categories = sortOptions(categoryOptionsByValue.values());

        return res;
    }

    private static void addOption(
        Map<String, PicklistOption> bucket,
        String label,
        String value
    ) {
        if (bucket == null || String.isBlank(value)) {
            return;
        }
        if (!bucket.containsKey(value)) {
            PicklistOption opt = new PicklistOption();
            opt.label = String.isNotBlank(label) ? label : value;
            opt.value = value;
            bucket.put(value, opt);
        }
    }

    private static List<PicklistOption> sortOptions(
        List<PicklistOption> options
    ) {
        if (options == null || options.isEmpty()) return new List<PicklistOption>();
        // Create a modifiable copy since Map.values() is unmodifiable
        List<PicklistOption> modifiableList = new List<PicklistOption>(options);
        modifiableList.sort(new PicklistOptionComparator());
        return modifiableList;
    }

    private class PicklistOptionComparator implements System.Comparator<PicklistOption> {
        public Integer compare(PicklistOption left, PicklistOption right) {
            String l = left != null && left.label != null ? left.label : '';
            String r = right != null && right.label != null ? right.label : '';
            return l.toLowerCase().compareTo(r.toLowerCase());
        }
    }

    private static String resolveFlatKey(Eligibility_Folder__c folder) {
        if (folder == null) return null;
        String key = EligibilityPathParser.normalizeFlatFolderKey(folder.Name);
        if (String.isBlank(key)) key = EligibilityPathParser.normalizeFlatFolderKey(folder.Folder_Type__c);
        if (String.isBlank(key)) key = EligibilityPathParser.normalizeFlatFolderKey(folder.Qualification_Type__c);
        if (String.isBlank(key)) key = EligibilityPathParser.normalizeFlatFolderKey(folder.Degree_Title__c);
        return key;
    }

    private static String toPathSegment(String raw) {
        if (String.isBlank(raw)) return raw;
        String seg = raw.trim().toLowerCase();
        seg = seg.replace(' ', '_').replace('-', '_');
        // Normalize marksheet variants to match expected folder path segment.
        if (seg == 'marksheet' || seg == 'marksheets' || seg == 'mark_sheet' || seg == 'mark_sheets') {
            return 'mark_sheets';
        }
        return seg;
    }
}