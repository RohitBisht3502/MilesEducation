/*
        Author       : ROHIT SINGH BISHT
        Description  : Update highest level on candidate
    */
public without sharing class CandidateHighestLevelUpdater {

    public static void updationOfHighestLevelOnCandidate(Set<Id> candidateIds) {
        System.debug('Updation of Highest level on Candidate => start');
        System.debug('candidateIds => ' + candidateIds);

        if (candidateIds == null || candidateIds.isEmpty()) {
            System.debug('No candidateIds found, exiting.');
            return;
        }

        List<Lead__c> childs = [SELECT Id, Candidate__c, Stage__c FROM Lead__c WHERE Candidate__c IN :candidateIds];

        System.debug('Child Lead__c fetched => ' + childs.size());

        Map<Id, Integer> bestRankByCandidate = new Map<Id, Integer>();
        Map<Id, String> bestStageByCandidate = new Map<Id, String>();
        Map<Id, String> bestBucketByCandidate = new Map<Id, String>();

        for (Lead__c c : childs) {
            if (c.Candidate__c == null || String.isBlank(c.Stage__c)) continue;

            Integer r = stageRank(c.Stage__c);
            String normalizedStage = normalize(c.Stage__c);
            String bucket = bucketFromStage(c.Stage__c);

            if (!bestRankByCandidate.containsKey(c.Candidate__c) || r > bestRankByCandidate.get(c.Candidate__c)) {
                bestRankByCandidate.put(c.Candidate__c, r);
                bestStageByCandidate.put(c.Candidate__c, normalizedStage);
                bestBucketByCandidate.put(c.Candidate__c, bucket);

                System.debug('Best updated => Candidate: ' + c.Candidate__c + ' Stage: ' + normalizedStage + ' Bucket: ' + bucket + ' Rank: ' + r);
            }
        }

        List<Lead> toUpdate = new List<Lead>();

        for (Id candId : candidateIds) {
            String bestStage = bestStageByCandidate.get(candId);
            String bestBucket = bestBucketByCandidate.get(candId);

            System.debug('Final for Candidate => ' + candId + ' Stage: ' + bestStage + ' Bucket: ' + bestBucket);

            Lead l = new Lead(
                Id = candId,
              //  Stage__c = bestStage,
                Engagement_Bucket__c = bestBucket
            );
            toUpdate.add(l);
        }

        System.debug('Leads to update => ' + toUpdate.size());

        if (!toUpdate.isEmpty()) {
            update toUpdate;
            System.debug('Updation of Highest level on Candidate => completed');
        } else {
            System.debug('Nothing to update.');
        }
    }

    private static String bucketFromStage(String stageRaw) {
        String s = normalize(stageRaw);
        Integer num = mNumber(s);

        if (num != null && num >= 8 && num <= 18) return 'Enrolled';
        if (s == 'M7' || s == 'M7+' || s == 'M7#') return 'Enrolled';
        if (s == 'M3+' || s == 'M3++' || s == 'M5' || s == 'M6') return 'Positive';
        if (s == 'M3') return 'Neutral';
        return 'Negative';
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
}