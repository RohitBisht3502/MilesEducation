/*
    Author       : Codex
    Description  : Invocable action for Lead__c New override flow.
*/
public with sharing class LeadNewOverrideInvocable {

    public class Request {
        @InvocableVariable(required=true)
        public Id recordTypeId;

        @InvocableVariable
        public String firstName;

        @InvocableVariable(required=true)
        public String lastName;

        @InvocableVariable(required=true)
        public String phone;

        @InvocableVariable(required=true)
        public String email;
    }

    public class Result {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String message;
        @InvocableVariable public Id leadId;
    }

    @InvocableMethod(
        label='Create Lead From Override'
        description='Creates Lead__c + Candidate (Lead), checks phone/email duplicates, and links Phone/Email as primary.'
    )
    public static List<Result> createLead(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;

        for (Request req : requests) {
            Result res = new Result();
            results.add(res);

            try {
                if (req == null) {
                    res.success = false;
                    res.message = 'Request is null.';
                    continue;
                }

                if (req.recordTypeId == null) {
                    res.success = false;
                    res.message = 'Record Type is required.';
                    continue;
                }
                if (String.isBlank(req.lastName) || String.isBlank(req.phone) || String.isBlank(req.email)) {
                    res.success = false;
                    res.message = 'Last Name, Phone, and Email are required.';
                    continue;
                }

                RecordType rt = [
                    SELECT Id, Name
                    FROM RecordType
                    WHERE Id = :req.recordTypeId AND SObjectType = 'Lead__c'
                    LIMIT 1
                ];
                if (rt == null) {
                    res.success = false;
                    res.message = 'Invalid Record Type.';
                    continue;
                }

                String course = getCourseFromRecordType(rt.Name);
                if (String.isBlank(course)) {
                    res.success = false;
                    res.message = 'Course mapping not found for Record Type: ' + rt.Name;
                    continue;
                }
                String stage = getDefaultStageForCourse(course);

                Phone_Number__c existingPhone = findExistingPhone(req.phone);
                if (existingPhone != null && existingPhone.Lead__c != null) {
                    res.success = false;
                    res.message = 'Phone number already exists with another Lead.';
                    continue;
                }

                Email__c existingEmail = findExistingEmail(req.email);
                if (existingEmail != null && existingEmail.Lead__c != null) {
                    res.success = false;
                    res.message = 'Email already exists with another Lead.';
                    continue;
                }

                Id candidateIdFromPhone = (existingPhone != null ? existingPhone.Candidate__c : null);
                Id candidateIdFromEmail = (existingEmail != null ? existingEmail.Candidate__c : null);
                if (candidateIdFromPhone != null && candidateIdFromEmail != null
                    && candidateIdFromPhone != candidateIdFromEmail) {
                    res.success = false;
                    res.message = 'Phone and Email belong to different candidates.';
                    continue;
                }

                Lead candidate = null;
                Id candidateIdToUse = (candidateIdFromPhone != null ? candidateIdFromPhone : candidateIdFromEmail);
                if (candidateIdToUse != null) {
                    List<Lead> candidates = [SELECT Id FROM Lead WHERE Id = :candidateIdToUse LIMIT 1];
                    if (!candidates.isEmpty()) candidate = candidates[0];
                }

                if (candidate == null) {
                    candidate = new Lead(
                        FirstName = req.firstName,
                        LastName  = req.lastName,
                        Company   = 'Miles Education',
                        Phone     = req.phone,
                        Email     = req.email
                    );
                    insert candidate;
                }

                String fullName = buildFullName(req.firstName, req.lastName);
                Lead__c newLead = new Lead__c(
                    Name         = fullName,
                    Phone__c     = req.phone,
                    Email__c     = req.email,
                    Stage__c     = stage,
                    Course__c    = course,
                    RecordTypeId = rt.Id,
                    Candidate__c = candidate.Id
                );
                insert newLead;

                if (existingPhone == null) {
                    Phone_Number__c phoneRec = new Phone_Number__c(
                        Name         = req.phone,
                        Phone__c     = req.phone,
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
                        Email__c     = req.email,
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
            } catch (Exception e) {
                res.success = false;
                res.message = e.getMessage();
            }
        }

        return results;
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

    private static String getDefaultStageForCourse(String course) {
        if (String.isBlank(course)) return 'M3';
        String courseKey = course.trim().toUpperCase();
        if (courseKey.contains('US PATHWAY')) return 'U3';
        if (courseKey.contains('MCOM')) return 'B3';
        if (courseKey.contains('CPA') || courseKey.contains('CMA') || courseKey.contains('CAIRA')) return 'M3';
        return 'M3';
    }
}
