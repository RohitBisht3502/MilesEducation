public with sharing class QueuePriorityService {

    public class QueueItemComparator implements System.Comparator<LeadQueueItemDTO> {
        public Integer compare(LeadQueueItemDTO a, LeadQueueItemDTO b) {
            Integer pa = (a.priority == null) ? 9999 : a.priority;
            Integer pb = (b.priority == null) ? 9999 : b.priority;

            if (pa != pb) {
                return (pa < pb) ? -1 : 1;
            }

            Datetime da = a.createdDate;
            Datetime db = b.createdDate;

            if (da == null && db == null) return 0;
            if (da == null) return 1;
            if (db == null) return -1;

            Long ta = da.getTime();
            Long tb = db.getTime();

            if (ta == tb) return 0;
            return (ta > tb) ? -1 : 1;
        }
    }

    public static List<LeadQueueItemDTO> assignPriorities(List<LeadQueueItemDTO> items) {
        System.debug('QueuePriorityService.assignPriorities: items size = ' + (items == null ? 0 : items.size()));
        List<LeadQueueItemDTO> output = new List<LeadQueueItemDTO>();
        if (items == null || items.isEmpty()) {
            return output;
        }

        User currentUser = [
            SELECT Id, UserRole.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        String currentUserRoleName = (currentUser.UserRole == null || String.isBlank(currentUser.UserRole.Name))
            ? null
            : currentUser.UserRole.Name.trim();
        String currentUserRoleUpper = currentUserRoleName == null ? null : currentUserRoleName.toUpperCase();
        System.debug('QueuePriorityService.assignPriorities: currentUserRoleName = ' + currentUserRoleName);

        if (String.isBlank(currentUserRoleName)) {
            System.debug('QueuePriorityService.assignPriorities: currentUserRoleName is blank -> returning empty list');
            return new List<LeadQueueItemDTO>();
        }

        List<Queue_Priority_Matrix__c> matrixRows = [
            SELECT Levels__c,
                   Queue_Priority__c,
                   Course_Tag__c,
                   Primary_tag__c,
                   Role_tag__c,
                   Source_Tag__c
            FROM Queue_Priority_Matrix__c
            WHERE Levels__c != null
              AND Queue_Priority__c != null
              AND Role_tag__c = :currentUserRoleName
        ];
        System.debug('QueuePriorityService.assignPriorities: matrixRows size = ' + matrixRows.size());

        Set<String> matrixRoles = new Set<String>();
        for (Queue_Priority_Matrix__c rowRole : matrixRows) {
            matrixRoles.addAll(parseMultiPicklist(rowRole.Role_tag__c));
        }
        System.debug('QueuePriorityService.assignPriorities: matrixRoles = ' + matrixRoles);

        for (LeadQueueItemDTO dto : items) {
            String dtoPrimary = String.isBlank(dto.primaryTag) ? null : dto.primaryTag.trim().toUpperCase();
            String dtoLevel   = String.isBlank(dto.stage)      ? null : dto.stage.trim().toUpperCase();
            String dtoSource  = String.isBlank(dto.source)     ? null : dto.source.trim().toUpperCase();
            String dtoCourse  = String.isBlank(dto.course)     ? null : dto.course.trim().toUpperCase();
            String dtoRole    = String.isBlank(dto.roleTag)    ? null : dto.roleTag.trim().toUpperCase();

            if (dtoRole == null && currentUserRoleUpper != null) {
                dtoRole = currentUserRoleUpper;
            }

            Integer bestPriority;
            Integer bestScore = -1;
            Id bestRowId;

            if (dtoRole == null || (!matrixRoles.isEmpty() && !matrixRoles.contains(dtoRole))) {
                System.debug(
                    'QueuePriorityService.assignPriorities: dto ' + dto.id +
                    ' skipped due to role, dtoRole=' + dtoRole +
                    ', currentUserRoleUpper=' + currentUserRoleUpper +
                    ', matrixRoles=' + matrixRoles
                );
                continue;
            }

            if (dtoPrimary == null || dtoLevel == null || dtoSource == null || dtoCourse == null) {
                System.debug(
                    'QueuePriorityService.assignPriorities: dto ' + dto.id +
                    ' missing one or more non-role tags, primary=' + dtoPrimary +
                    ', level=' + dtoLevel +
                    ', source=' + dtoSource +
                    ', course=' + dtoCourse +
                    ', role=' + dtoRole +
                    ' => no priority, will be pushed to end'
                );
                dto.priority = null;
                output.add(dto);
                continue;
            }

            for (Queue_Priority_Matrix__c row : matrixRows) {
                String rowPrimary = String.isBlank(row.Primary_tag__c) ? null : row.Primary_tag__c.trim().toUpperCase();
                if (rowPrimary == null || rowPrimary != dtoPrimary) {
                    continue;
                }

                Set<String> rowLevels = parseMultiPicklist(row.Levels__c);
                if (rowLevels.isEmpty() || !rowLevels.contains(dtoLevel)) {
                    continue;
                }

                Set<String> rowSources = parseMultiPicklistWithAll(row.Source_Tag__c);
                Boolean sourceMatch;
                if (rowSources.isEmpty()) {
                    sourceMatch = true;
                } else {
                    sourceMatch = rowSources.contains(dtoSource);
                }

                Set<String> rowCourses = parseMultiPicklistWithAll(row.Course_Tag__c);
                Boolean courseMatch;
                if (rowCourses.isEmpty()) {
                    courseMatch = true;
                } else {
                    courseMatch = rowCourses.contains(dtoCourse);
                }

                Set<String> rowRoles = parseMultiPicklistWithAll(row.Role_tag__c);
                Boolean roleMatch;
                if (rowRoles.isEmpty()) {
                    roleMatch = true;
                } else {
                    roleMatch = rowRoles.contains(dtoRole);
                }

                // if (!sourceMatch && !courseMatch && !roleMatch) {
                //     continue;
                // }
                if (!sourceMatch || !courseMatch || !roleMatch) {
                    continue;
                }

                Integer score = 0;
                if (sourceMatch) score++;
                if (courseMatch) score++;
                if (roleMatch)   score++;

                Integer q = Integer.valueOf(row.Queue_Priority__c);

                if (bestPriority == null || q < bestPriority || (q == bestPriority && score > bestScore)) {
                    bestPriority = q;
                    bestScore = score;
                    bestRowId = row.Id;
                }
            }

            dto.priority = bestPriority;
            System.debug(
                'QueuePriorityService.assignPriorities: dtoId=' + dto.id +
                ', primary=' + dtoPrimary +
                ', level=' + dtoLevel +
                ', source=' + dtoSource +
                ', course=' + dtoCourse +
                ', role=' + dtoRole +
                ', bestPriority=' + bestPriority +
                ', bestScore=' + bestScore +
                ', bestRowId=' + bestRowId
            );
            output.add(dto);
        }

        output.sort(new QueueItemComparator());
        System.debug('QueuePriorityService.assignPriorities: final output size=' + output.size());
        return output;
    }

    private static Set<String> parseMultiPicklist(String value) {
        Set<String> result = new Set<String>();
        if (String.isBlank(value)) {
            return result;
        }
        for (String token : value.split('[;,]')) {
            String t = token == null ? null : token.trim();
            if (!String.isBlank(t)) {
                result.add(t.toUpperCase());
            }
        }
        System.debug('QueuePriorityService.parseMultiPicklist: value=' + value + ', parsed=' + result);
        return result;
    }

    private static Set<String> parseMultiPicklistWithAll(String value) {
        Set<String> base = parseMultiPicklist(value);
        if (base.contains('ALL')) {
            base.clear();
        }
        System.debug('QueuePriorityService.parseMultiPicklistWithAll: value=' + value + ', parsedWithAll=' + base);
        return base;
    }
}