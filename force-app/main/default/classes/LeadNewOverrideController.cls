/*
    Author       : Codex
    Description  : Aura controller for Lead__c New override.
*/
public with sharing class LeadNewOverrideController {

    public class RecordTypeOption {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        public RecordTypeOption(String id, String name) {
            this.id = id;
            this.name = name;
        }
    }

    public class CourseOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public CourseOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class Result {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id leadId;
    }

    @AuraEnabled(cacheable=true)
    public static List<RecordTypeOption> getLeadRecordTypes() {
        List<RecordTypeOption> out = new List<RecordTypeOption>();
        for (RecordType rt : [
            SELECT Id, Name
            FROM RecordType
            WHERE SObjectType = 'Lead__c' AND IsActive = true
            ORDER BY Name
        ]) {
            out.add(new RecordTypeOption(rt.Id, rt.Name));
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<CourseOption> getLeadCourses() {
        Map<String, String> courseByKey = new Map<String, String>();
        for (RecordType rt : [
            SELECT Id, Name
            FROM RecordType
            WHERE SObjectType = 'Lead__c' AND IsActive = true
            ORDER BY Name
        ]) {
            String course = getCourseFromRecordType(rt.Name);
            if (String.isBlank(course)) continue;
            String key = course.trim().toUpperCase();
            if (!courseByKey.containsKey(key)) {
                courseByKey.put(key, course.trim());
            }
        }

        List<String> labels = new List<String>();
        labels.addAll(courseByKey.values());
        labels.sort();

        List<CourseOption> options = new List<CourseOption>();
        for (String label : labels) {
            options.add(new CourseOption(label, label));
        }
        return options;
    }

    @AuraEnabled
    public static Result createLeadByCourse(String course, String firstName, String lastName, String phone, String email) {
        Result res = new Result();
        try {
            if (String.isBlank(course)) {
                throw new AuraHandledException('Course is required.');
            }
            if (String.isBlank(lastName) || String.isBlank(phone) || String.isBlank(email)) {
                throw new AuraHandledException('Last Name, Phone, and Email are required.');
            }

            Id recordTypeId = getRecordTypeIdForCourse(course);
            if (recordTypeId == null) {
                throw new AuraHandledException('Record Type not found for Course: ' + course);
            }
            String stage = getDefaultStageForCourse(course);

            Lead__c existingLead = findExistingLeadByPhone(phone);
            if (existingLead != null) {
                throw new AuraHandledException('Lead already exists with this phone number.');
            }

            Phone_Number__c existingPhone = findExistingPhone(phone);
            if (existingPhone != null && existingPhone.Lead__c != null) {
                throw new AuraHandledException('Phone number already exists with another Lead.');
            }

            Email__c existingEmail = findExistingEmail(email);
            if (existingEmail != null && existingEmail.Lead__c != null) {
                throw new AuraHandledException('Email already exists with another Lead.');
            }

            Id candidateIdFromPhone = (existingPhone != null ? existingPhone.Candidate__c : null);
            Id candidateIdFromEmail = (existingEmail != null ? existingEmail.Candidate__c : null);
            if (candidateIdFromPhone != null && candidateIdFromEmail != null
                && candidateIdFromPhone != candidateIdFromEmail) {
                throw new AuraHandledException('Phone and Email belong to different candidates.');
            }

            Lead candidate = null;
            Id candidateIdToUse = (candidateIdFromPhone != null ? candidateIdFromPhone : candidateIdFromEmail);
            if (candidateIdToUse != null) {
                List<Lead> candidates = [SELECT Id FROM Lead WHERE Id = :candidateIdToUse LIMIT 1];
                if (!candidates.isEmpty()) candidate = candidates[0];
            }

            if (candidate == null) {
                candidate = new Lead(
                    FirstName = firstName,
                    LastName  = lastName,
                    Company   = 'Miles Education',
                    Phone     = phone,
                    Email     = email
                );
                insert candidate;
            }

            String fullName = buildFullName(firstName, lastName);
            Lead__c newLead = new Lead__c(
                Name         = fullName,
                Phone__c     = phone,
                Email__c     = email,
                Stage__c     = stage,
                Course__c    = course,
                RecordTypeId = recordTypeId,
                Candidate__c = candidate.Id
            );
            insert newLead;

            if (existingPhone == null) {
                Phone_Number__c phoneRec = new Phone_Number__c(
                    Name         = phone,
                    Phone__c     = phone,
                    Lead__c      = newLead.Id,
                    Candidate__c = candidate.Id,
                    Is_Primary__c= true
                );
                insert phoneRec;
            } else {
                Boolean phoneChanged = false;
                if (existingPhone.Lead__c == null) {
                    existingPhone.Lead__c = newLead.Id;
                    phoneChanged = true;
                }
                if (existingPhone.Candidate__c == null) {
                    existingPhone.Candidate__c = candidate.Id;
                    phoneChanged = true;
                }
                if (existingPhone.Is_Primary__c != true) {
                    existingPhone.Is_Primary__c = true;
                    phoneChanged = true;
                }
                if (phoneChanged) update existingPhone;
            }

            if (existingEmail == null) {
                Email__c emailRec = new Email__c(
                    Email__c     = email,
                    Lead__c      = newLead.Id,
                    Candidate__c = candidate.Id,
                    Is_Primary__c= true
                );
                insert emailRec;
            } else {
                Boolean emailChanged = false;
                if (existingEmail.Lead__c == null) {
                    existingEmail.Lead__c = newLead.Id;
                    emailChanged = true;
                }
                if (existingEmail.Candidate__c == null) {
                    existingEmail.Candidate__c = candidate.Id;
                    emailChanged = true;
                }
                if (existingEmail.Is_Primary__c != true) {
                    existingEmail.Is_Primary__c = true;
                    emailChanged = true;
                }
                if (emailChanged) update existingEmail;
            }

            res.success = true;
            res.message = 'Lead created.';
            res.leadId = newLead.Id;
            return res;

        } catch (AuraHandledException ahe) {
            res.success = false;
            res.message = ahe.getMessage();
            return res;
        } catch (Exception e) {
            res.success = false;
            res.message = e.getMessage();
            return res;
        }
    }

    @AuraEnabled
    public static Result createLead(Id recordTypeId, String firstName, String lastName, String phone, String email) {
        Result res = new Result();
        try {
            if (recordTypeId == null) {
                throw new AuraHandledException('Record Type is required.');
            }
            if (String.isBlank(lastName) || String.isBlank(phone) || String.isBlank(email)) {
                throw new AuraHandledException('Last Name, Phone, and Email are required.');
            }

            RecordType rt = [
                SELECT Id, Name
                FROM RecordType
                WHERE Id = :recordTypeId AND SObjectType = 'Lead__c'
                LIMIT 1
            ];

            String course = getCourseFromRecordType(rt.Name);
            if (String.isBlank(course)) {
                throw new AuraHandledException('Course mapping not found for Record Type: ' + rt.Name);
            }
            String stage = getDefaultStageForCourse(course);

            Phone_Number__c existingPhone = findExistingPhone(phone);
            if (existingPhone != null && existingPhone.Lead__c != null) {
                throw new AuraHandledException('Phone number already exists with another Lead.');
            }

            Email__c existingEmail = findExistingEmail(email);
            if (existingEmail != null && existingEmail.Lead__c != null) {
                throw new AuraHandledException('Email already exists with another Lead.');
            }

            Id candidateIdFromPhone = (existingPhone != null ? existingPhone.Candidate__c : null);
            Id candidateIdFromEmail = (existingEmail != null ? existingEmail.Candidate__c : null);
            if (candidateIdFromPhone != null && candidateIdFromEmail != null
                && candidateIdFromPhone != candidateIdFromEmail) {
                throw new AuraHandledException('Phone and Email belong to different candidates.');
            }

            Lead candidate = null;
            Id candidateIdToUse = (candidateIdFromPhone != null ? candidateIdFromPhone : candidateIdFromEmail);
            if (candidateIdToUse != null) {
                List<Lead> candidates = [SELECT Id FROM Lead WHERE Id = :candidateIdToUse LIMIT 1];
                if (!candidates.isEmpty()) candidate = candidates[0];
            }

            if (candidate == null) {
                candidate = new Lead(
                    FirstName = firstName,
                    LastName  = lastName,
                    Company   = 'Miles Education',
                    Phone     = phone,
                    Email     = email
                );
                insert candidate;
            }

            String fullName = buildFullName(firstName, lastName);
            Lead__c newLead = new Lead__c(
                Name         = fullName,
                Phone__c     = phone,
                Email__c     = email,
                Stage__c     = stage,
                Course__c    = course,
                RecordTypeId = rt.Id,
                Candidate__c = candidate.Id
            );
            insert newLead;

            if (existingPhone == null) {
                Phone_Number__c phoneRec = new Phone_Number__c(
                    Name         = phone,
                    Phone__c     = phone,
                    Lead__c      = newLead.Id,
                    Candidate__c = candidate.Id,
                    Is_Primary__c= true
                );
                insert phoneRec;
            } else {
                Boolean phoneChanged = false;
                if (existingPhone.Lead__c == null) {
                    existingPhone.Lead__c = newLead.Id;
                    phoneChanged = true;
                }
                if (existingPhone.Candidate__c == null) {
                    existingPhone.Candidate__c = candidate.Id;
                    phoneChanged = true;
                }
                if (existingPhone.Is_Primary__c != true) {
                    existingPhone.Is_Primary__c = true;
                    phoneChanged = true;
                }
                if (phoneChanged) update existingPhone;
            }

            if (existingEmail == null) {
                Email__c emailRec = new Email__c(
                    Email__c     = email,
                    Lead__c      = newLead.Id,
                    Candidate__c = candidate.Id,
                    Is_Primary__c= true
                );
                insert emailRec;
            } else {
                Boolean emailChanged = false;
                if (existingEmail.Lead__c == null) {
                    existingEmail.Lead__c = newLead.Id;
                    emailChanged = true;
                }
                if (existingEmail.Candidate__c == null) {
                    existingEmail.Candidate__c = candidate.Id;
                    emailChanged = true;
                }
                if (existingEmail.Is_Primary__c != true) {
                    existingEmail.Is_Primary__c = true;
                    emailChanged = true;
                }
                if (emailChanged) update existingEmail;
            }

            res.success = true;
            res.message = 'Lead created.';
            res.leadId = newLead.Id;
            return res;

        } catch (AuraHandledException ahe) {
            res.success = false;
            res.message = ahe.getMessage();
            return res;
        } catch (Exception e) {
            res.success = false;
            res.message = e.getMessage();
            return res;
        }
    }

    private static String buildFullName(String firstName, String lastName) {
        String name = '';
        if (!String.isBlank(firstName)) name = firstName.trim();
        if (!String.isBlank(lastName)) {
            if (String.isBlank(name)) {
                name = lastName.trim();
            } else {
                name = name + ' ' + lastName.trim();
            }
        }
        return name;
    }

    private static Phone_Number__c findExistingPhone(String rawPhone) {
        if (String.isBlank(rawPhone)) return null;

        Set<String> variants = Utility.buildPhoneVariants(rawPhone);
        String digits = rawPhone.replaceAll('[^0-9]', '');
        String last10 = null;
        if (!String.isBlank(digits)) {
            last10 = (digits.length() > 10) ? digits.substring(digits.length() - 10) : digits;
        }

        List<Phone_Number__c> matches;
        if (!String.isBlank(last10)) {
            String likePattern = '%' + last10;
            matches = [
                SELECT Id, Lead__c, Candidate__c, Phone__c, Is_Primary__c
                FROM Phone_Number__c
                WHERE (Phone__c IN :variants OR Phone__c LIKE :likePattern)
                LIMIT 1
            ];
        } else if (!variants.isEmpty()) {
            matches = [
                SELECT Id, Lead__c, Candidate__c, Phone__c, Is_Primary__c
                FROM Phone_Number__c
                WHERE Phone__c IN :variants
                LIMIT 1
            ];
        } else {
            return null;
        }

        return matches.isEmpty() ? null : matches[0];
    }

    private static Lead__c findExistingLeadByPhone(String rawPhone) {
        if (String.isBlank(rawPhone)) return null;

        Set<String> variants = Utility.buildPhoneVariants(rawPhone);
        String digits = rawPhone.replaceAll('[^0-9]', '');
        String last10 = null;
        if (!String.isBlank(digits)) {
            last10 = (digits.length() > 10) ? digits.substring(digits.length() - 10) : digits;
        }

        List<Lead__c> matches;
        if (!String.isBlank(last10)) {
            String likePattern = '%' + last10;
            matches = [
                SELECT Id, Phone__c
                FROM Lead__c
                WHERE (Phone__c IN :variants OR Phone__c LIKE :likePattern)
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        } else if (!variants.isEmpty()) {
            matches = [
                SELECT Id, Phone__c
                FROM Lead__c
                WHERE Phone__c IN :variants
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        } else {
            return null;
        }

        return matches.isEmpty() ? null : matches[0];
    }

    private static Email__c findExistingEmail(String email) {
        if (String.isBlank(email)) return null;
        List<Email__c> emails = [
            SELECT Id, Lead__c, Candidate__c, Is_Primary__c
            FROM Email__c
            WHERE Email__c = :email
            LIMIT 1
        ];
        return emails.isEmpty() ? null : emails[0];
    }

    private static String getCourseFromRecordType(String recordTypeName) {
        if (String.isBlank(recordTypeName)) return null;
        String raw = recordTypeName.trim();
        String rt = raw.toUpperCase();
        if (rt.contains('US PATHWAY')) return raw;
        if (rt.contains('CPA')) return raw;
        if (rt.contains('CMA')) return raw;
        if (rt.contains('CAIRA')) return raw;
        if (rt.contains('MCOM')) return raw;
        return null;
    }

    private static Id getRecordTypeIdForCourse(String course) {
        if (String.isBlank(course)) return null;
        String courseKey = course.trim().toUpperCase();
        for (RecordType rt : [
            SELECT Id, Name
            FROM RecordType
            WHERE SObjectType = 'Lead__c' AND IsActive = true
        ]) {
            String mapped = getCourseFromRecordType(rt.Name);
            if (String.isBlank(mapped)) continue;
            if (mapped.trim().toUpperCase() == courseKey) {
                return rt.Id;
            }
        }
        return null;
    }

    private static String getDefaultStageForCourse(String course) {
        if (String.isBlank(course)) return 'M3';
        String courseKey = course.trim().toUpperCase();
        if (courseKey.contains('US PATHWAY')) return 'U3';
        if (courseKey.contains('MCOM')) return 'B3';
        if (courseKey.contains('CPA') || courseKey.contains('CMA') || courseKey.contains('CAIRA')) return 'M3';
        return 'M3';
    }
}