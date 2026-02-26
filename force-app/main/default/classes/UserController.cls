/**
* @File Name : UserController.cls
* @Description :
* @Author :
* @Last Modified By :
* @Last Modified On : October 7, 2025
* @Modification Log :
*==============================================================================
* Ver | Date | Author | Modification
*==============================================================================
* 1.0 | October 7, 2025 |   | Initial Version
**/

public class UserController {
    @AuraEnabled(cacheable=true)
    public static User getCurrentUserInfo() {
        return [
            SELECT Id, Name, Email, Title, SmallPhotoUrl,
                   ManagerId, Manager.Name, Manager.Email,
                   Manager.ManagerId, Manager.Manager.Name, Manager.Manager.Email
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
    }
    
    @AuraEnabled(cacheable=true)
    public static List<User> getAvailableUsers() {
        return [SELECT Id, Name, Email, Title, SmallPhotoUrl FROM User WHERE IsActive = true  AND Email != null  ORDER BY Name LIMIT 200];
    }
}