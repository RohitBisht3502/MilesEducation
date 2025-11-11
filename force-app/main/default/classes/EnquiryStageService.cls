public class EnquiryStageService {

    public static void validateStageTransitions(List<Enquiry__c> newList, Map<Id, Enquiry__c> oldMap) {
        if (newList == null || newList.isEmpty()) return;

        Set<String> oldStages = new Set<String>();
        Set<String> programs = new Set<String>();
        Map<Id, String> newStageById = new Map<Id, String>();
        Map<Id, String> programById = new Map<Id, String>();

        for (Enquiry__c rec : newList) {
            Enquiry__c oldRec = oldMap.get(rec.Id);
            if (oldRec == null) continue;

            String oldStage = oldRec.Stage__c;
            String newStage = rec.Stage__c;
            String program = rec.Course__c;

            if (String.isBlank(oldStage) || String.isBlank(newStage) || oldStage == newStage) continue;

            oldStages.add(oldStage);
            if (!String.isBlank(program)) programs.add(program);

            newStageById.put(rec.Id, newStage);
            programById.put(rec.Id, program);
        }

        if (oldStages.isEmpty()) return;

        Map<String, Map<String, Set<String>>> rulesByProgram = new Map<String, Map<String, Set<String>>>();

        if (!programs.isEmpty()) {
            for (LevelManagment__c rule :
                [SELECT Program_Name__c, Stages__c, New_Stage__c
                 FROM LevelManagment__c
                 WHERE Stages__c IN :oldStages
                 AND Program_Name__c IN :programs]) {

                if (String.isBlank(rule.Program_Name__c) || String.isBlank(rule.Stages__c)) continue;

                Map<String, Set<String>> byStage = rulesByProgram.get(rule.Program_Name__c);
                if (byStage == null) {
                    byStage = new Map<String, Set<String>>();
                    rulesByProgram.put(rule.Program_Name__c, byStage);
                }

                Set<String> allowed = byStage.get(rule.Stages__c);
                if (allowed == null) {
                    allowed = new Set<String>();
                    byStage.put(rule.Stages__c, allowed);
                }

                if (!String.isBlank(rule.New_Stage__c)) {
                    for (String s : rule.New_Stage__c.split(';')) {
                        String t = s == null ? null : s.trim();
                        if (!String.isBlank(t)) allowed.add(t);
                    }
                }
            }
        }

        for (Enquiry__c rec : newList) {
            if (!newStageById.containsKey(rec.Id)) continue;

            String fromStage = oldMap.get(rec.Id).Stage__c;
            String toStage = newStageById.get(rec.Id);
            String program = programById.get(rec.Id);

            if (String.isBlank(program)) {
              //  rec.Course__c.addError('Program (Course__c) is required to validate stage transition.');
                continue;
            }

            Map<String, Set<String>> byStage = rulesByProgram.get(program);
            if (byStage == null) {
              //  rec.Stage__c.addError('No stage transition rules found for Program "' + program + '".');
                continue;
            }

            Set<String> allowed = byStage.get(fromStage);
            if (allowed == null || allowed.isEmpty()) {
             //   rec.Stage__c.addError('No valid transitions for Program "' + program + '" and Stage "' + fromStage + '".');
                continue;
            }

            if (!allowed.contains(toStage)) {
                rec.Stage__c.addError('Stage change from "' + fromStage + '" to "' + toStage + '" is not allowed for Program "' + program + '".');
            }
        }
    }
}