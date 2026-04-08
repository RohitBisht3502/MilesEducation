// file: force-app/main/default/classes/StudentGPFileController.cls
public without sharing class StudentGPFileController {

    public class FileNode {
        @AuraEnabled public Id id;
        @AuraEnabled public String name; // This will now hold the actual file name
        @AuraEnabled public String label; // This will hold the standard record name (e.g., File Status - 0003)
        @AuraEnabled public String status;
        @AuraEnabled public String filePath;
        @AuraEnabled public String fileType;
        @AuraEnabled public String iconName;
        @AuraEnabled public String statusClass;
    }

    public class FolderNode {
        @AuraEnabled public String id; 
        @ AuraEnabled public String name;
        @AuraEnabled public List<FolderNode> children;
        @AuraEnabled public List<FileNode> files;
        @AuraEnabled public Boolean expanded;
        @AuraEnabled public Integer level;

        public FolderNode(String id, String name, Integer level) {
            this.id = id;
            this.name = name;
            this.level = level;
            this.children = new List<FolderNode>();
            this.files = new List<FileNode>();
            this.expanded = false;
        }
    }

    public class CourseNode {
        @AuraEnabled public String courseName;
        @AuraEnabled public String step;
        @AuraEnabled public List<FolderNode> folderTree;
    }

    @AuraEnabled(cacheable=true)
    public static List<CourseNode> getStudentFileTree(Id accountId) {
        if (accountId == null) return new List<CourseNode>();

        // changes by rohit - 2026-04-07: support Account, Candidate, and Lead__c with direct SOQL only
        List<Student_File_Status__c> records = new List<Student_File_Status__c>();
        Schema.SObjectType recordType = accountId.getSObjectType();
        Map<String, Schema.SObjectField> fieldMap = Student_File_Status__c.SObjectType.getDescribe().fields.getMap();

        if (recordType == Account.SObjectType && fieldMap.containsKey('Student__c')) {
            records = [SELECT Id, Name, Status__c, File_Path__c, File_Type__c, Course__c, GP_Folder__r.Step__c FROM Student_File_Status__c WHERE Student__c = :accountId ORDER BY Course__c, File_Path__c];
        } else if (recordType == Lead.SObjectType && fieldMap.containsKey('Candidate__c')) {
            records = [SELECT Id, Name, Status__c, File_Path__c, File_Type__c, Course__c, GP_Folder__r.Step__c FROM Student_File_Status__c WHERE Candidate__c = :accountId ORDER BY Course__c, File_Path__c];
        } else if (recordType == Lead__c.SObjectType && fieldMap.containsKey('Lead__c')) {
            records = [SELECT Id, Name, Status__c, File_Path__c, File_Type__c, Course__c, GP_Folder__r.Step__c FROM Student_File_Status__c WHERE Lead__c = :accountId ORDER BY Course__c, File_Path__c];
        } else {
            return new List<CourseNode>();
        }

        Map<String, List<Student_File_Status__c>> courseToRecords = new Map<String, List<Student_File_Status__c>>();
        for (Student_File_Status__c r : records) {
            String course = String.isNotBlank(r.Course__c) ? r.Course__c : 'General';
            if (!courseToRecords.containsKey(course)) {
                courseToRecords.put(course, new List<Student_File_Status__c>());
            }
            courseToRecords.get(course).add(r);
        }

        List<CourseNode> courseNodes = new List<CourseNode>();
        for (String course : courseToRecords.keySet()) {
            CourseNode cn = new CourseNode();
            cn.courseName = course;
            
            List<Student_File_Status__c> courseRecords = courseToRecords.get(course);
            // Get the first available step for this course
            cn.step = 'N/A';
            for (Student_File_Status__c r : courseRecords) {
                if (r.GP_Folder__r != null && String.isNotBlank(r.GP_Folder__r.Step__c)) {
                    cn.step = r.GP_Folder__r.Step__c;
                    break;
                }
            }
            
            cn.folderTree = buildTreeFromPaths(courseRecords);
            courseNodes.add(cn);
        }

        return courseNodes;
    }

    private static List<FolderNode> buildTreeFromPaths(List<Student_File_Status__c> records) {
        FolderNode root = new FolderNode('root', 'Root', 0);
        
        for (Student_File_Status__c r : records) {
            String path = r.File_Path__c;
            if (String.isBlank(path)) {
                root.files.add(mapToFileNode(r));
                continue;
            }

            List<String> parts = path.split('/');
            FolderNode current = root;
            String currentPath = '';

            for (Integer i = 0; i < parts.size() - 1; i++) {
                String folderName = parts[i];
                // Skip the first part if it's a UUID to keep the tree clean
                if (i == 0 && isValidUUID(folderName)) {
                    continue; 
                }
                
                currentPath += (String.isBlank(currentPath) ? '' : '/') + folderName;
                FolderNode next = findOrCreateChild(current, currentPath, folderName);
                current = next;
            }
            
            current.files.add(mapToFileNode(r));
        }

        return root.children.isEmpty() && !root.files.isEmpty() ? new List<FolderNode>{root} : root.children;
    }

    private static Boolean isValidUUID(String str) {
        if (String.isBlank(str)) return false;
        // Lenient check: skip folders that are 25+ chars (standard IDs/UUIDs) 
        // or have a UUID-like dash pattern.
        return str.length() >= 25 || (str.contains('-') && str.length() >= 18);
    }

    private static FolderNode findOrCreateChild(FolderNode parent, String path, String folderName) {
        for (FolderNode child : parent.children) {
            if (child.id == path) return child;
        }
        FolderNode newNode = new FolderNode(path, folderName, parent.level + 1);
        parent.children.add(newNode);
        return newNode;
    }

    private static FileNode mapToFileNode(Student_File_Status__c r) {
        FileNode fn = new FileNode();
        fn.id = r.Id;
        fn.label = r.Name; // Standard name (e.g., File Status - 0003)
        fn.name = extractActualName(r.File_Path__c, r.Name); // Actual filename
        fn.status = r.Status__c;
        fn.filePath = r.File_Path__c;
        fn.fileType = r.File_Type__c;
        fn.iconName = iconNameForFile(fn.name);
        fn.statusClass = statusClassForFile(r.Status__c);
        return fn;
    }

    private static String extractActualName(String path, String defaultName) {
        if (String.isBlank(path)) return defaultName;
        List<String> parts = path.split('/');
        if (parts.isEmpty()) return defaultName;
        String fileName = parts[parts.size() - 1];
        return String.isNotBlank(fileName) ? fileName : defaultName;
    }
    private static String iconNameForFile(String fileName) {
        if (String.isBlank(fileName)) return 'doctype:attachment';
        String ext = fileName.substringAfterLast('.').toLowerCase();
        if (ext == 'pdf') return 'doctype:pdf';
        if (new Set<String>{'png', 'jpg', 'jpeg', 'gif'}.contains(ext)) return 'doctype:image';
        if (new Set<String>{'doc', 'docx'}.contains(ext)) return 'doctype:word';
        if (new Set<String>{'xls', 'xlsx', 'csv'}.contains(ext)) return 'doctype:excel';
        return 'doctype:attachment';
    }

    private static String statusClassForFile(String status) {
        if (String.isBlank(status)) return 'status-submitted';
        String s = status.toLowerCase();
        if (s == 'verified' || s == 'approved') return 'status-verified';
        if (s.contains('recheck') || s.contains('not applicable')) return 'status-recheck';
        return 'status-submitted';
    }
}