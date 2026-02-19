/*
        Author       : ROHIT SINGH BISHT
        Description  : Update highest level on student account
    */
public without sharing class AccountHighestLevelUpdater {

    public static void updationOfHighestLevelOnAccount(Set<Id> studentIds) {
        System.debug('Updation of Highest level on Account => start');
        System.debug('studentIds => ' + studentIds);

        if (studentIds == null || studentIds.isEmpty()) {
            System.debug('No studentIds found, exiting.');
            return;
        }

        List<Lead__c> childs = [
            SELECT Id, Student__c, Stage__c, Course__c
            FROM Lead__c
            WHERE Student__c IN :studentIds
        ];

        System.debug('Child Lead__c fetched => ' + childs.size());

        Map<Id, Integer> bestRankByStudent = new Map<Id, Integer>();
        Map<Id, String> bestStageByStudent = new Map<Id, String>();

        Map<String, Integer> bestRankByStudentCourse = new Map<String, Integer>();
        Map<String, String> bestStageByStudentCourse = new Map<String, String>();

        for (Lead__c c : childs) {
            if (c.Student__c == null || String.isBlank(c.Stage__c)) continue;

            Integer r = stageRank(c.Stage__c);
            String normalizedStage = normalize(c.Stage__c);

            if (!bestRankByStudent.containsKey(c.Student__c) || r > bestRankByStudent.get(c.Student__c)) {
                bestRankByStudent.put(c.Student__c, r);
                bestStageByStudent.put(c.Student__c, normalizedStage);
            }

            if (!String.isBlank(c.Course__c)) {
                String courseKey = buildStudentCourseKey(c.Student__c, c.Course__c);
                if (!bestRankByStudentCourse.containsKey(courseKey) || r > bestRankByStudentCourse.get(courseKey)) {
                    bestRankByStudentCourse.put(courseKey, r);
                    bestStageByStudentCourse.put(courseKey, normalizedStage);
                }
            }
        }

        List<Account> toUpdate = new List<Account>();
        Map<String, Schema.SObjectField> accFieldMap = Account.SObjectType.getDescribe().fields.getMap();

        for (Id studentId : studentIds) {
            String bestStage = bestStageByStudent.get(studentId);

            Account acc = new Account(Id = studentId);

            // Overall highest level across all courses
            setIfPresent(acc, accFieldMap, 'Highest_Level__c', bestStage);

            // Course-wise highest levels
            setCourseLevel(acc, accFieldMap, studentId, 'CAIRA', 'CAIRA_Level__c', bestStageByStudentCourse);
            setCourseLevel(acc, accFieldMap, studentId, 'CPA', 'CPA_Level__c', bestStageByStudentCourse);
            setCourseLevel(acc, accFieldMap, studentId, 'CMA', 'CMA_Level__c', bestStageByStudentCourse);
            setCourseLevel(acc, accFieldMap, studentId, 'US PATHWAY', 'USP_Level__c', bestStageByStudentCourse);

            toUpdate.add(acc);
        }

        System.debug('Accounts to update => ' + toUpdate.size());

        if (!toUpdate.isEmpty()) {
            update toUpdate;
            System.debug('Updation of Highest level on Account => completed');
        } else {
            System.debug('Nothing to update.');
        }
    }

    private static Integer stageRank(String stageRaw) {
        String s = normalize(stageRaw);
        Integer num = mNumber(s);

        if (num != null && num >= 8 && num <= 18) return 500 + num;

        if (s == 'M7')  return 470;
        if (s == 'M7+') return 471;
        if (s == 'M7#') return 472;

        if (s == 'M6')   return 360;
        if (s == 'M5')   return 350;
        if (s == 'M3++') return 332;
        if (s == 'M3+')  return 331;

        if (s == 'M3') return 230;

        if (s == 'M4')  return 141;
        if (s == 'M4-') return 140;
        if (s == 'M2')  return 120;
        if (s == 'M1')  return 110;

        return 0;
    }

    private static String normalize(String raw) {
        String s = raw == null ? '' : raw.trim().toUpperCase();
        s = s.replace(' ', '');
        s = s.replace('PLUSPLUS', '++');
        s = s.replace('PLUS', '+');
        s = s.replace('MINUS', '-');
        s = s.replace('HASH', '#');
        return s;
    }

    private static Integer mNumber(String s) {
        if (String.isBlank(s) || !s.startsWith('M')) return null;
        String digits = '';
        for (Integer i = 1; i < s.length(); i++) {
            String ch = s.substring(i, i + 1);
            if (ch >= '0' && ch <= '9') digits += ch;
            else break;
        }
        if (String.isBlank(digits)) return null;
        try { return Integer.valueOf(digits); } catch (Exception e) { return null; }
    }

    private static String buildStudentCourseKey(Id studentId, String course) {
        return String.valueOf(studentId) + '||' + normalizeCourse(course);
    }

    private static String normalizeCourse(String raw) {
        return String.isBlank(raw) ? null : raw.trim().toUpperCase();
    }

    private static void setCourseLevel(
        Account acc,
        Map<String, Schema.SObjectField> fieldMap,
        Id studentId,
        String course,
        String fieldApiName,
        Map<String, String> bestStageByStudentCourse
    ) {
        if (acc == null || fieldMap == null || !fieldMap.containsKey(fieldApiName)) return;
        String key = buildStudentCourseKey(studentId, course);
        String stage = bestStageByStudentCourse.get(key);
        setIfPresent(acc, fieldMap, fieldApiName, stage);
    }

    private static void setIfPresent(SObject sobj, Map<String, Schema.SObjectField> fieldMap, String fieldApiName, Object value) {
        if (sobj == null || fieldMap == null || String.isBlank(fieldApiName)) return;
        if (!fieldMap.containsKey(fieldApiName)) return;
        sobj.put(fieldApiName, value);
    }
}